import 'dart:async';
import 'dart:io';

import 'package:rxdart/rxdart.dart';

import '../models/app_config.dart';
import '../models/cloud_provider.dart';
import '../models/cloud_secrets.dart';
import '../models/playback_snapshot.dart';
import '../models/recorder_snapshot.dart';
import '../models/recording_segment.dart';
import '../services/background_capture_service.dart';
import '../services/playback_service.dart';
import '../services/s3_storage_client.dart';
import '../services/segment_index.dart';
import '../services/segment_recorder.dart';
import '../services/settings_store.dart';
import 'app_view_model.dart';

class AppController {
  factory AppController({
    SettingsStore? settingsStore,
    SegmentIndex? segmentIndex,
    SegmentRecorder? recorder,
    PlaybackService? playback,
    BackgroundCaptureService? backgroundCaptureService,
    S3StorageClient? s3StorageClient,
  }) {
    final effectiveSegmentIndex = segmentIndex ?? SegmentIndex();
    return AppController._(
      settingsStore: settingsStore ?? SettingsStore(),
      segmentIndex: effectiveSegmentIndex,
      recorder:
          recorder ?? SegmentRecorder(segmentIndex: effectiveSegmentIndex),
      playback: playback ?? PlaybackService(),
      backgroundCaptureService:
          backgroundCaptureService ?? BackgroundCaptureService(),
      s3StorageClient: s3StorageClient ?? S3StorageClient(),
    );
  }

  AppController._({
    required this._settingsStore,
    required this._segmentIndex,
    required this._recorder,
    required this._playback,
    required this._backgroundCaptureService,
    required this._s3StorageClient,
  }) {
    _viewModels =
        Rx.combineLatest8<
              AppConfig,
              CloudSecrets,
              List<RecordingSegment>,
              RecorderSnapshot,
              PlaybackSnapshot,
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
              _isInitializing,
              _isUploading,
              _message,
              (
                config,
                secrets,
                segments,
                recorder,
                playback,
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
  StreamSubscription<dynamic>? _uploadSubscription;

  Stream<AppViewModel> get viewModels => _viewModels;

  Future<void> init() async {
    _backgroundCaptureService.init();
    final config = await _settingsStore.loadConfig();
    final secrets = await _settingsStore.loadSecrets();
    final recovered = await _segmentIndex.recoverOrphanedLocalSegments(
      fallbackSegmentMinutes: config.segmentMinutes,
    );
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
      bitRate: config.bitRate.clamp(16000, 320000),
      sampleRate: config.sampleRate.clamp(8000, 48000),
      channels: config.channels.clamp(1, 2),
      s3Bucket: config.s3Bucket.trim(),
      s3Region: config.s3Region.trim(),
      s3Prefix: config.s3Prefix.trim(),
      s3Endpoint: config.s3Endpoint.trim(),
    );
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
    );
    await _settingsStore.saveSecrets(normalized);
    _secrets.add(normalized);
    _message.add('Cloud credentials saved.');
    requestUploadDrain();
  }

  Future<void> startRecording() async {
    final backgroundError = await _backgroundCaptureService.start();
    if (backgroundError != null) {
      _message.add(backgroundError);
      return;
    }
    try {
      await _recorder.start(_config.value);
      _message.add('Recording started.');
    } catch (error) {
      await _backgroundCaptureService.stop();
      _message.add(error.toString());
    }
  }

  Future<void> stopRecording() async {
    Object? recorderError;
    try {
      await _recorder.stop();
    } catch (error) {
      recorderError = error;
    } finally {
      await _backgroundCaptureService.stop();
    }
    _message.add(
      recorderError == null
          ? 'Recording stopped.'
          : 'Foreground service stopped after recorder error: $recorderError',
    );
    requestUploadDrain();
  }

  Future<void> playLocalWindow() async {
    await _playback.playSegments(_segments.value);
  }

  Future<void> pausePlayback() => _playback.pause();

  Future<void> stopPlayback() => _playback.stop();

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
    await _uploadSubscription?.cancel();
    await _uploadRequests.close();
    await _recorder.dispose();
    await _playback.dispose();
    _s3StorageClient.close();
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
    if (config.cloudProvider != CloudProvider.s3) {
      _message.add(
        '${config.cloudProvider.label} configuration is saved; upload support is not implemented yet.',
      );
      return;
    }
    if (!config.s3TargetReady || !secrets.hasS3Credentials) {
      _message.add(
        'S3 bucket, region, access key, and secret key are required before uploads can run.',
      );
      return;
    }
    _isUploading.add(true);
    try {
      final segments = await _segmentIndex.loadSegments();
      final pending =
          segments
              .where(
                (segment) =>
                    segment.localPath != null &&
                    (segment.uploadStatus == SegmentUploadStatus.pending ||
                        segment.uploadStatus == SegmentUploadStatus.failed),
              )
              .toList()
            ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
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
          result = await _s3StorageClient.uploadSegment(
            config: config,
            secrets: secrets,
            segment: uploading,
            file: File(localPath),
          );
        } catch (error) {
          result = UploadResult.failure('S3 upload failed: $error');
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
    if (config.cloudProvider == CloudProvider.s3 &&
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
