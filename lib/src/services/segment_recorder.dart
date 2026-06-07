import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';
import 'package:rxdart/rxdart.dart';

import '../models/app_config.dart';
import '../models/recorder_snapshot.dart';
import '../models/recording_segment.dart';
import 'segment_index.dart';

class SegmentRecorder {
  SegmentRecorder({AudioRecorder? recorder, required SegmentIndex segmentIndex})
    : this._(recorder ?? AudioRecorder(), segmentIndex);

  SegmentRecorder._(this._recorder, this._segmentIndex);

  final AudioRecorder _recorder;
  final SegmentIndex _segmentIndex;
  final BehaviorSubject<RecorderSnapshot> _snapshot = BehaviorSubject.seeded(
    const RecorderSnapshot.idle(),
  );
  final PublishSubject<RecordingSegment> _closedSegments = PublishSubject();

  Timer? _rotationTimer;
  StreamSubscription<dynamic>? _amplitudeSubscription;
  DateTime? _activeStartedAtUtc;
  String? _activePath;
  bool _running = false;
  bool _rotating = false;

  ValueStream<RecorderSnapshot> get snapshots => _snapshot.stream;

  Stream<RecordingSegment> get closedSegments => _closedSegments.stream;

  bool get isRecording => _running;

  Future<void> start(AppConfig config) async {
    if (_running) {
      return;
    }
    _snapshot.add(_snapshot.value.copyWith(isStarting: true, error: null));
    try {
      await _configureAudioSession();
      final hasPermission = await _recorder.hasPermission(request: true);
      if (!hasPermission) {
        throw StateError('Microphone permission was not granted.');
      }
      final supported = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
      if (!supported) {
        throw StateError('AAC-LC recording is not supported on this device.');
      }
      _running = true;
      await _startNewSegment(config);
    } catch (error) {
      _running = false;
      _snapshot.add(
        const RecorderSnapshot.idle().copyWith(error: error.toString()),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running && _activePath == null) {
      return;
    }
    _running = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    await _finishActiveSegment();
    _snapshot.add(const RecorderSnapshot.idle());
  }

  Future<void> dispose() async {
    await stop();
    await _amplitudeSubscription?.cancel();
    await _snapshot.close();
    await _closedSegments.close();
    await _recorder.dispose();
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
  }

  Future<void> _startNewSegment(AppConfig config) async {
    final startedAtUtc = DateTime.now().toUtc();
    final path = await _segmentIndex.createSegmentPath(startedAtUtc);
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: config.bitRate,
        sampleRate: config.sampleRate,
        numChannels: config.channels,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
        audioInterruption: AudioInterruptionMode.pauseResume,
      ),
      path: path,
    );
    _activeStartedAtUtc = startedAtUtc;
    _activePath = path;
    _snapshot.add(
      RecorderSnapshot(
        isRecording: true,
        isStarting: false,
        activeSegmentPath: path,
        activeSegmentStartedAtUtc: startedAtUtc,
      ),
    );
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 500))
        .listen((amplitude) {
          final current = _snapshot.value;
          _snapshot.add(
            current.copyWith(
              averageDb: amplitude.current,
              peakDb: amplitude.max,
              error: null,
            ),
          );
        });
    _rotationTimer?.cancel();
    _rotationTimer = Timer(config.segmentDuration, () => _rotate(config));
  }

  Future<void> _rotate(AppConfig config) async {
    if (!_running || _rotating) {
      return;
    }
    _rotating = true;
    try {
      await _finishActiveSegment();
      if (_running) {
        await _startNewSegment(config);
      }
    } catch (error) {
      _running = false;
      _snapshot.add(
        _snapshot.value.copyWith(
          isRecording: false,
          isStarting: false,
          error: error.toString(),
        ),
      );
    } finally {
      _rotating = false;
    }
  }

  Future<void> _finishActiveSegment() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final startedAtUtc = _activeStartedAtUtc;
    final activePath = _activePath;
    if (startedAtUtc == null || activePath == null) {
      return;
    }
    String? stoppedPath;
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      stoppedPath = await _recorder.stop();
    }
    final path = stoppedPath ?? activePath;
    final file = File(path);
    final stat = await file.exists() ? await file.stat() : null;
    final endedAtUtc = DateTime.now().toUtc();
    final segment = RecordingSegment(
      id: SegmentIndex.safeSegmentId(startedAtUtc),
      startedAtUtc: startedAtUtc,
      endedAtUtc: endedAtUtc,
      localPath: path,
      byteSize: stat?.size ?? 0,
      uploadStatus: SegmentUploadStatus.pending,
    );
    _activeStartedAtUtc = null;
    _activePath = null;
    if (segment.byteSize > 0) {
      _closedSegments.add(segment);
    }
  }
}
