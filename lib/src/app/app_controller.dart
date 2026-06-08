import 'dart:async';
import 'dart:io';

import 'package:rxdart/rxdart.dart';

import '../models/audio_trigger_event.dart';
import '../models/app_config.dart';
import '../models/cloud_provider.dart';
import '../models/cloud_secrets.dart';
import '../models/playback_snapshot.dart';
import '../models/recorder_snapshot.dart';
import '../models/recording_segment.dart';
import '../services/background_capture_service.dart';
import '../services/diagnostic_log.dart';
import '../services/playback_service.dart';
import '../services/s3_storage_client.dart';
import '../services/segment_index.dart';
import '../services/segment_recorder.dart';
import '../services/settings_store.dart';
import '../services/sound_recorder_backend_client.dart';
import 'app_view_model.dart';

class AppController {
  factory AppController({
    SettingsStore? settingsStore,
    SegmentIndex? segmentIndex,
    SegmentRecorder? recorder,
    PlaybackService? playback,
    BackgroundCaptureService? backgroundCaptureService,
    S3StorageClient? s3StorageClient,
    SoundRecorderBackendClient? backendClient,
    DiagnosticLog? diagnosticLog,
  }) {
    final effectiveSegmentIndex = segmentIndex ?? SegmentIndex();
    final effectiveDiagnostics = diagnosticLog ?? DiagnosticLog();
    return AppController._(
      settingsStore: settingsStore ?? SettingsStore(),
      segmentIndex: effectiveSegmentIndex,
      recorder:
          recorder ?? SegmentRecorder(segmentIndex: effectiveSegmentIndex),
      playback: playback ?? PlaybackService(),
      backgroundCaptureService:
          backgroundCaptureService ??
          BackgroundCaptureService(diagnostics: effectiveDiagnostics),
      s3StorageClient: s3StorageClient ?? S3StorageClient(),
      backendClient: backendClient ?? SoundRecorderBackendClient(),
      diagnostics: effectiveDiagnostics,
    );
  }

  AppController._({
    required this._settingsStore,
    required this._segmentIndex,
    required this._recorder,
    required this._playback,
    required this._backgroundCaptureService,
    required this._s3StorageClient,
    required this._backendClient,
    required this._diagnostics,
  }) {
    _viewModels =
        Rx.combineLatest9<
              AppConfig,
              CloudSecrets,
              List<RecordingSegment>,
              RecorderSnapshot,
              PlaybackSnapshot,
              List<String>,
              bool,
              bool,
              String?,
              AppViewModel
            >(
              _config,
              _secrets,
              _segments,
              _recorder.snapshots,
              _playback.snapshots,
              _diagnostics.entries,
              _isInitializing,
              _isUploading,
              _message,
              (
                config,
                secrets,
                segments,
                recorder,
                playback,
                diagnosticEntries,
                isInitializing,
                isUploading,
                message,
              ) {
                return AppViewModel(
                  config: config,
                  secrets: secrets,
                  segments: segments,
                  recorder: recorder,
                  playback: playback,
                  diagnosticEntries: diagnosticEntries,
                  isInitializing: isInitializing,
                  isUploading: isUploading,
                  message: message,
                );
              },
            )
            .shareReplay(maxSize: 1);
  }

  final SettingsStore _settingsStore;
  final SegmentIndex _segmentIndex;
  final SegmentRecorder _recorder;
  final PlaybackService _playback;
  final BackgroundCaptureService _backgroundCaptureService;
  final S3StorageClient _s3StorageClient;
  final SoundRecorderBackendClient _backendClient;
  final DiagnosticLog _diagnostics;

  final BehaviorSubject<AppConfig> _config = BehaviorSubject();
  final BehaviorSubject<CloudSecrets> _secrets = BehaviorSubject();
  final BehaviorSubject<List<RecordingSegment>> _segments =
      BehaviorSubject.seeded(const []);
  final BehaviorSubject<bool> _isInitializing = BehaviorSubject.seeded(true);
  final BehaviorSubject<bool> _isUploading = BehaviorSubject.seeded(false);
  final BehaviorSubject<String?> _message = BehaviorSubject.seeded(null);
  final PublishSubject<void> _uploadRequests = PublishSubject();

  late final Stream<AppViewModel> _viewModels;
  StreamSubscription<void>? _closedSegmentsSubscription;
  StreamSubscription<dynamic>? _triggerSubscription;
  StreamSubscription<dynamic>? _uploadSubscription;
  BackendUploadSession? _backendSession;
  String? _backendSessionKey;
  final List<AudioTriggerEvent> _pendingAlertEvents = [];

  Stream<AppViewModel> get viewModels => _viewModels;

  Future<void> init() async {
    _diagnostics.add('App controller init started.');
    _backgroundCaptureService.init();
    final config = await _settingsStore.loadConfig();
    final secrets = await _settingsStore.loadSecrets();
    final pendingAlerts = await _settingsStore.loadPendingAlerts();
    final recovered = await _segmentIndex.recoverOrphanedLocalSegments(
      fallbackSegmentMinutes: config.segmentMinutes,
    );
    _pendingAlertEvents
      ..clear()
      ..addAll(pendingAlerts);
    _config.add(config);
    _secrets.add(secrets);
    _segments.add(recovered);
    _closedSegmentsSubscription = _recorder.closedSegments
        .asyncMap(_onSegmentClosed)
        .listen(
          (_) {},
          onError: (Object error) {
            _message.add('Failed to index a closed segment: $error');
          },
        );
    _triggerSubscription = _recorder.triggerEvents
        .asyncMap((event) => _sendAlertForEvent(event))
        .listen(
          (_) {},
          onError: (Object error) {
            _message.add('Audio alert failed: $error');
          },
        );
    _uploadSubscription = _uploadRequests
        .debounceTime(const Duration(milliseconds: 250))
        .exhaustMap((_) => Stream.fromFuture(_drainUploads()))
        .listen(
          (_) {},
          onError: (Object error) {
            _message.add('Upload queue failed: $error');
            _isUploading.add(false);
          },
        );
    _isInitializing.add(false);
    _diagnostics.add('App controller init completed.');
    requestUploadDrain();
    await _enforceRetention();
  }

  Future<void> saveConfig(AppConfig config) async {
    final deviceRetentionHours = config.deviceRetentionHours.clamp(1, 500);
    final cloudRetentionHours = config.cloudRetentionHours.clamp(
      deviceRetentionHours,
      2000,
    );
    final normalized = config.copyWith(
      deviceRetentionHours: deviceRetentionHours,
      cloudRetentionHours: cloudRetentionHours,
      segmentMinutes: config.segmentMinutes.clamp(1, 60),
      overlapSeconds: config.overlapSeconds.clamp(0, 30),
      bitRate: config.bitRate.clamp(16000, 320000),
      sampleRate: config.sampleRate.clamp(8000, 48000),
      channels: config.channels.clamp(1, 2),
      backendBaseUrl: config.backendBaseUrl.trim(),
      s3Bucket: config.s3Bucket.trim(),
      s3Region: config.s3Region.trim(),
      s3Prefix: config.s3Prefix.trim(),
      s3Endpoint: config.s3Endpoint.trim(),
    );
    if (_backendSessionKey != _sessionKey(normalized, _secrets.valueOrNull)) {
      _backendSession = null;
      _backendSessionKey = null;
    }
    await _settingsStore.saveConfig(normalized);
    _config.add(normalized);
    _message.add('Settings saved.');
    requestUploadDrain();
    await _enforceRetention();
  }

  Future<void> saveSecrets(CloudSecrets secrets) async {
    final normalized = CloudSecrets(
      s3AccessKeyId: secrets.s3AccessKeyId.trim(),
      s3SecretAccessKey: secrets.s3SecretAccessKey.trim(),
      s3SessionToken: secrets.s3SessionToken.trim(),
      backendDeviceToken: secrets.backendDeviceToken.trim(),
    );
    if (_backendSessionKey != _sessionKey(_config.valueOrNull, normalized)) {
      _backendSession = null;
      _backendSessionKey = null;
    }
    await _settingsStore.saveSecrets(normalized);
    _secrets.add(normalized);
    _message.add('Cloud credentials saved.');
    requestUploadDrain();
  }

  Future<void> startRecording() async {
    _diagnostics.add('Start recording requested.');
    final backgroundError = await _backgroundCaptureService.start();
    if (backgroundError != null) {
      _diagnostics.add(backgroundError);
    }
    try {
      _diagnostics.add('Starting PCM microphone stream.');
      await _recorder.start(_config.value);
      _diagnostics.add('PCM microphone stream started.');
      _message.add(
        backgroundError == null
            ? 'Recording started.'
            : 'Recording started locally. $backgroundError',
      );
    } catch (error) {
      _diagnostics.add('Recorder start failed: $error.');
      await _backgroundCaptureService.stop();
      _message.add(error.toString());
    }
  }

  Future<void> stopRecording() async {
    _diagnostics.add('Stop recording requested.');
    Object? recorderError;
    try {
      await _recorder.stop();
      _diagnostics.add('PCM microphone stream stopped.');
    } catch (error) {
      recorderError = error;
      _diagnostics.add('Recorder stop failed: $error.');
    } finally {
      await _backgroundCaptureService.stop();
    }
    _message.add(
      recorderError == null
          ? 'Recording stopped.'
          : 'Foreground service stopped after recorder error: $recorderError',
    );
    _diagnostics.add('Stop recording completed.');
    requestUploadDrain();
  }

  Future<void> playLocalWindow() async {
    await _playback.playSegments(_segments.value);
  }

  Future<void> pausePlayback() => _playback.pause();

  Future<void> stopPlayback() => _playback.stop();

  Future<void> sendManualAlert() {
    return _sendAlertForEvent(
      AudioTriggerEvent(
        type: AudioTriggerType.manual,
        occurredAtUtc: DateTime.now().toUtc(),
        captureSessionId: '',
        sampleIndex: 0,
      ),
      userVisible: true,
    );
  }

  void requestUploadDrain() {
    if (!_uploadRequests.isClosed) {
      _uploadRequests.add(null);
    }
  }

  Future<void> clearMessage() async {
    _message.add(null);
  }

  Future<void> dispose() async {
    await _closedSegmentsSubscription?.cancel();
    await _triggerSubscription?.cancel();
    await _uploadSubscription?.cancel();
    await _uploadRequests.close();
    await _recorder.dispose();
    await _playback.dispose();
    _s3StorageClient.close();
    _backendClient.close();
    await _diagnostics.dispose();
    await _config.close();
    await _secrets.close();
    await _segments.close();
    await _isInitializing.close();
    await _isUploading.close();
    await _message.close();
  }

  Future<void> _onSegmentClosed(RecordingSegment segment) async {
    await _segmentIndex.upsertSegment(segment);
    final nextSegments = await _segmentIndex.loadSegments();
    _segments.add(nextSegments);
    requestUploadDrain();
    await _enforceRetention();
  }

  Future<void> _drainUploads() async {
    if (_isUploading.value) {
      return;
    }
    if (!_config.hasValue || !_secrets.hasValue) {
      return;
    }
    final config = _config.value;
    final secrets = _secrets.value;
    if (!config.uploadEnabled) {
      return;
    }
    final segments = await _segmentIndex.loadSegments();
    final pending =
        segments
            .where(
              (segment) =>
                  segment.localPath != null &&
                  (segment.uploadStatus == SegmentUploadStatus.pending ||
                      segment.uploadStatus == SegmentUploadStatus.uploading ||
                      segment.uploadStatus == SegmentUploadStatus.failed),
            )
            .toList()
          ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    final useBackend = _backendClient.canUseBackend(config, secrets);
    if (!useBackend && config.cloudProvider != CloudProvider.s3) {
      final message =
          '${config.cloudProvider.label} requires the sound recorder backend URL and device token.';
      _diagnostics.add(message);
      if (pending.isNotEmpty) {
        _message.add(message);
      }
      return;
    }
    if (!useBackend && (!config.s3TargetReady || !secrets.hasS3Credentials)) {
      const message =
          'S3 bucket, region, access key, and secret key are required before uploads can run.';
      _diagnostics.add(message);
      if (pending.isNotEmpty) {
        _message.add(message);
      }
      return;
    }
    _isUploading.add(true);
    try {
      for (final segment in pending) {
        final localPath = segment.localPath;
        if (localPath == null) {
          continue;
        }
        var uploading = segment.copyWith(
          uploadStatus: SegmentUploadStatus.uploading,
          error: null,
        );
        await _replaceSegment(uploading);
        late final UploadResult result;
        try {
          if (useBackend) {
            final backendResult = await _uploadViaBackend(
              config: config,
              secrets: secrets,
              segment: uploading,
              file: File(localPath),
            );
            result = backendResult.isSuccess
                ? UploadResult.success(backendResult.remoteKey!)
                : UploadResult.failure(backendResult.error);
          } else {
            result = await _s3StorageClient.uploadSegment(
              config: config,
              secrets: secrets,
              segment: uploading,
              file: File(localPath),
            );
          }
        } catch (error) {
          result = UploadResult.failure('Upload failed: $error');
        }
        final updated = result.isSuccess
            ? uploading.copyWith(
                uploadStatus: SegmentUploadStatus.uploaded,
                remoteKey: result.remoteKey,
                uploadedAtUtc: DateTime.now().toUtc(),
                error: null,
              )
            : uploading.copyWith(
                uploadStatus: SegmentUploadStatus.failed,
                error: result.error,
              );
        await _replaceSegment(updated);
      }
      _message.add(
        pending.isEmpty ? 'No pending uploads.' : 'Upload queue drained.',
      );
      await _flushPendingAlerts();
      await _enforceRetention();
    } catch (error) {
      _message.add('Upload queue failed: $error');
    } finally {
      _isUploading.add(false);
    }
  }

  Future<void> _replaceSegment(RecordingSegment segment) async {
    final segments = [..._segments.value];
    final index = segments.indexWhere((item) => item.id == segment.id);
    if (index == -1) {
      segments.add(segment);
    } else {
      segments[index] = segment;
    }
    segments.sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    await _segmentIndex.saveSegments(segments);
    _segments.add(segments);
  }

  Future<BackendUploadResult> _uploadViaBackend({
    required AppConfig config,
    required CloudSecrets secrets,
    required RecordingSegment segment,
    required File file,
  }) async {
    var session = _backendSession;
    if (session == null || !session.isUsable) {
      session = await _backendClient.createUploadSession(
        config: config,
        secrets: secrets,
      );
      _backendSession = session;
      _backendSessionKey = _sessionKey(config, secrets);
    }
    var result = await _backendClient.uploadSegment(
      config: config,
      secrets: secrets,
      session: session,
      segment: segment,
      file: file,
    );
    if (!result.isSuccess && result.error?.contains('expired') == true) {
      session = await _backendClient.createUploadSession(
        config: config,
        secrets: secrets,
      );
      _backendSession = session;
      _backendSessionKey = _sessionKey(config, secrets);
      result = await _backendClient.uploadSegment(
        config: config,
        secrets: secrets,
        session: session,
        segment: segment,
        file: file,
      );
    }
    if (result.session != null) {
      _backendSession = result.session;
      _backendSessionKey = _sessionKey(config, secrets);
    }
    return result;
  }

  Future<void> _sendAlertForEvent(
    AudioTriggerEvent event, {
    bool userVisible = false,
  }) async {
    if (!_config.hasValue || !_secrets.hasValue) {
      return;
    }
    final config = _config.value;
    final secrets = _secrets.value;
    if (!_backendClient.canUseBackend(config, secrets)) {
      if (userVisible) {
        _message.add(
          'Backend URL and device token are required before alert emails can be sent.',
        );
      }
      return;
    }
    final segments = _alertReadySegments(event);
    if (segments.isEmpty) {
      await _queueAlert(event);
      requestUploadDrain();
      if (userVisible) {
        _message.add('Alert queued until matching audio is uploaded.');
      }
      return;
    }
    final segment = segments.isEmpty ? null : segments.last;
    final error = await _backendClient.postAlert(
      config: config,
      secrets: secrets,
      trigger: event.serverTrigger,
      occurredAtUtc: event.occurredAtUtc,
      segmentId: segment?.id,
      sequence: segment?.sequence,
      metadata: event.metadata,
    );
    if (error != null) {
      if (userVisible || event.type != AudioTriggerType.commotion) {
        _message.add(error);
      }
      return;
    }
    _pendingAlertEvents.remove(event);
    await _persistPendingAlerts();
    if (userVisible) {
      _message.add('Alert email requested.');
    }
  }

  List<RecordingSegment> _alertReadySegments(AudioTriggerEvent event) {
    final listenFrom = event.occurredAtUtc.subtract(
      const Duration(seconds: 20),
    );
    final listenTo = event.occurredAtUtc.add(const Duration(seconds: 90));
    final segments =
        _segments.value
            .where(
              (segment) =>
                  segment.uploadStatus == SegmentUploadStatus.uploaded &&
                  segment.remoteKey != null &&
                  segment.endedAtUtc.isAfter(listenFrom) &&
                  segment.startedAtUtc.isBefore(listenTo),
            )
            .toList()
          ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    return segments;
  }

  Future<void> _queueAlert(AudioTriggerEvent event) async {
    final alreadyQueued = _pendingAlertEvents.any(
      (queued) =>
          queued.type == event.type &&
          queued.occurredAtUtc == event.occurredAtUtc &&
          queued.sampleIndex == event.sampleIndex,
    );
    if (!alreadyQueued) {
      _pendingAlertEvents.add(event);
    }
    if (_pendingAlertEvents.length > 20) {
      _pendingAlertEvents.removeRange(0, _pendingAlertEvents.length - 20);
    }
    await _persistPendingAlerts();
  }

  Future<void> _persistPendingAlerts() async {
    await _settingsStore.savePendingAlerts(_pendingAlertEvents);
  }

  Future<void> _flushPendingAlerts() async {
    if (_pendingAlertEvents.isEmpty) {
      return;
    }
    final pending = [..._pendingAlertEvents];
    for (final event in pending) {
      if (_alertReadySegments(event).isNotEmpty) {
        await _sendAlertForEvent(event);
      }
    }
  }

  String? _sessionKey(AppConfig? config, CloudSecrets? secrets) {
    if (config == null || secrets == null) {
      return null;
    }
    if (!_backendClient.canUseBackend(config, secrets)) {
      return null;
    }
    return '${config.backendBaseUrl.trim()}|${secrets.backendDeviceToken.trim()}';
  }

  Future<void> _enforceRetention() async {
    if (!_config.hasValue || !_secrets.hasValue) {
      return;
    }
    final config = _config.value;
    final now = DateTime.now().toUtc();
    var segments = await _segmentIndex.enforceDeviceRetention(
      segments: await _segmentIndex.loadSegments(),
      cutoffUtc: now.subtract(Duration(hours: config.deviceRetentionHours)),
    );
    if (!_backendClient.canUseBackend(config, _secrets.value) &&
        config.cloudProvider == CloudProvider.s3 &&
        config.s3TargetReady &&
        _secrets.value.hasS3Credentials) {
      final cutoffUtc = now.subtract(
        Duration(hours: config.cloudRetentionHours),
      );
      final next = <RecordingSegment>[];
      for (final segment in segments) {
        if (segment.remoteKey != null &&
            segment.endedAtUtc.isBefore(cutoffUtc)) {
          final error = await _s3StorageClient.deleteObject(
            config: config,
            secrets: _secrets.value,
            key: segment.remoteKey!,
          );
          if (error == null) {
            next.add(
              segment.copyWith(
                remoteKey: null,
                uploadedAtUtc: null,
                uploadStatus: segment.isLocal
                    ? SegmentUploadStatus.localOnly
                    : SegmentUploadStatus.uploaded,
              ),
            );
          } else {
            next.add(segment.copyWith(error: error));
          }
        } else {
          next.add(segment);
        }
      }
      segments = await _segmentIndex.dropCloudExpiredRecords(
        segments: next,
        cutoffUtc: cutoffUtc,
      );
    }
    _segments.add(segments);
  }
}
