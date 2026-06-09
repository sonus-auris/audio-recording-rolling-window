import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_trigger_event.dart';
import '../models/app_config.dart';
import '../models/recorder_snapshot.dart';
import '../models/recording_segment.dart';
import 'segment_index.dart';
import 'wav_segment_writer.dart';

class SegmentRecorder {
  SegmentRecorder({
    AudioRecorder? recorder,
    required SegmentIndex segmentIndex,
    Uuid? uuid,
  }) : this._(recorder ?? AudioRecorder(), segmentIndex, uuid ?? const Uuid());

  SegmentRecorder._(this._recorder, this._segmentIndex, this._uuid);

  final AudioRecorder _recorder;
  final SegmentIndex _segmentIndex;
  final Uuid _uuid;
  final BehaviorSubject<RecorderSnapshot> _snapshot = BehaviorSubject.seeded(
    const RecorderSnapshot.idle(),
  );
  final PublishSubject<RecordingSegment> _closedSegments = PublishSubject();
  final PublishSubject<AudioTriggerEvent> _triggerEvents = PublishSubject();

  StreamSubscription<void>? _recordStreamSubscription;
  StreamSubscription<dynamic>? _amplitudeSubscription;
  Completer<void>? _streamDone;
  AppConfig? _config;
  DateTime? _captureStartedAtUtc;
  String? _captureSessionId;
  WavSegmentWriter? _writer;
  DateTime? _writerStartedAtUtc;
  String? _writerPath;
  Uint8List _overlapBytes = Uint8List(0);
  Uint8List _remainderBytes = Uint8List(0);
  int _currentOverlapSamples = 0;
  int _currentUniqueSamples = 0;
  int _currentStartSample = 0;
  int _totalLiveSamples = 0;
  int _sequence = 0;
  int _commotionSamples = 0;
  DateTime? _lastCommotionAlertUtc;
  bool _running = false;
  bool _stopping = false;
  _AudioDsp? _dsp;

  ValueStream<RecorderSnapshot> get snapshots => _snapshot.stream;

  Stream<RecordingSegment> get closedSegments => _closedSegments.stream;

  Stream<AudioTriggerEvent> get triggerEvents => _triggerEvents.stream;

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
      final supported = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supported) {
        throw StateError(
          'PCM16 stream recording is not supported on this device.',
        );
      }
      _resetCaptureState(config);
      _running = true;
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: config.sampleRate,
          numChannels: config.channels,
          // Music capture keeps dynamics: platform AGC/denoise default off.
          autoGain: config.autoGain,
          echoCancel: false,
          noiseSuppress: config.noiseSuppress,
          audioInterruption: AudioInterruptionMode.pauseResume,
          streamBufferSize: _streamBufferSize(config),
        ),
      );
      _streamDone = Completer<void>();
      _recordStreamSubscription = stream
          .asyncMap(_handlePcmBytes)
          .listen(
            (_) {},
            onError: (Object error) {
              _snapshot.add(
                _snapshot.value.copyWith(
                  isRecording: false,
                  isStarting: false,
                  error: error.toString(),
                ),
              );
              _running = false;
              _completeStreamDone();
            },
            onDone: _completeStreamDone,
            cancelOnError: false,
          );
      _snapshot.add(
        RecorderSnapshot(
          isRecording: true,
          isStarting: false,
          activeSegmentStartedAtUtc: _captureStartedAtUtc,
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
    } catch (error) {
      _running = false;
      _snapshot.add(
        const RecorderSnapshot.idle().copyWith(error: error.toString()),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    if ((!_running && _writer == null) || _stopping) {
      return;
    }
    _stopping = true;
    _running = false;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    try {
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.stop();
      }
      final done = _streamDone;
      if (done != null && !done.isCompleted) {
        await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      }
      await _flushRemainder();
      await _finishActiveSegment();
      await _recordStreamSubscription?.cancel();
      _recordStreamSubscription = null;
    } finally {
      _stopping = false;
      _snapshot.add(const RecorderSnapshot.idle());
    }
  }

  Future<void> dispose() async {
    await stop();
    await _snapshot.close();
    await _closedSegments.close();
    await _triggerEvents.close();
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

  void _resetCaptureState(AppConfig config) {
    _config = config;
    _captureStartedAtUtc = DateTime.now().toUtc();
    _captureSessionId = _uuid.v4();
    _writer = null;
    _writerStartedAtUtc = null;
    _writerPath = null;
    _overlapBytes = Uint8List(0);
    _remainderBytes = Uint8List(0);
    _currentOverlapSamples = 0;
    _currentUniqueSamples = 0;
    _currentStartSample = 0;
    _totalLiveSamples = 0;
    _sequence = 0;
    _commotionSamples = 0;
    _lastCommotionAlertUtc = null;
    _dsp = _AudioDsp.fromConfig(config);
  }

  int _streamBufferSize(AppConfig config) {
    final frameSize = config.channels * 2;
    final frames = (config.sampleRate / 10).round().clamp(512, 4096);
    return frames * frameSize;
  }

  Future<void> _handlePcmBytes(Uint8List bytes) async {
    final config = _config;
    if (!_running || config == null || bytes.isEmpty) {
      return;
    }
    final frameSize = config.channels * 2;
    final data = _consumeAlignedFrames(bytes, frameSize);
    var offset = 0;
    while (offset < data.length && _running) {
      await _ensureWriter();
      final writer = _writer;
      if (writer == null) {
        return;
      }
      final remainingSamples = config.samplesPerSegment - _currentUniqueSamples;
      if (remainingSamples <= 0) {
        await _finishActiveSegment();
        continue;
      }
      final availableSamples = (data.length - offset) ~/ frameSize;
      final takeSamples = math.min(availableSamples, remainingSamples);
      if (takeSamples <= 0) {
        return;
      }
      final end = offset + takeSamples * frameSize;
      final rawSlice = Uint8List.sublistView(data, offset, end);
      // Apply client-side gain + tone shaping so stored audio, overlap, and the
      // loudness trigger all see the same processed signal.
      final slice = _dsp?.process(rawSlice, config.channels) ?? rawSlice;
      await writer.write(slice);
      _currentUniqueSamples += takeSamples;
      _totalLiveSamples += takeSamples;
      _rememberOverlap(slice, config.overlapSamples, frameSize);
      _detectCommotion(slice, takeSamples);
      offset = end;
      if (_currentUniqueSamples >= config.samplesPerSegment) {
        await _finishActiveSegment();
      }
    }
  }

  Uint8List _consumeAlignedFrames(Uint8List bytes, int frameSize) {
    final combined = _remainderBytes.isEmpty
        ? bytes
        : Uint8List.fromList([..._remainderBytes, ...bytes]);
    final alignedLength = combined.length - combined.length % frameSize;
    if (alignedLength == combined.length) {
      _remainderBytes = Uint8List(0);
      return combined;
    }
    _remainderBytes = Uint8List.fromList(combined.sublist(alignedLength));
    return Uint8List.fromList(combined.sublist(0, alignedLength));
  }

  Future<void> _flushRemainder() async {
    final config = _config;
    if (config == null || _remainderBytes.isEmpty) {
      _remainderBytes = Uint8List(0);
      return;
    }
    final frameSize = config.channels * 2;
    final alignedLength =
        _remainderBytes.length - _remainderBytes.length % frameSize;
    if (alignedLength > 0) {
      final aligned = Uint8List.fromList(
        _remainderBytes.sublist(0, alignedLength),
      );
      _remainderBytes = Uint8List(0);
      final wasRunning = _running;
      _running = true;
      await _handlePcmBytes(aligned);
      _running = wasRunning;
    }
    _remainderBytes = Uint8List(0);
  }

  Future<void> _ensureWriter() async {
    if (_writer != null) {
      return;
    }
    final config = _config;
    final captureStartedAt = _captureStartedAtUtc;
    if (config == null || captureStartedAt == null) {
      return;
    }
    _currentStartSample = _totalLiveSamples;
    _currentUniqueSamples = 0;
    _currentOverlapSamples = math.min(
      _overlapBytes.length ~/ (config.channels * 2),
      config.overlapSamples,
    );
    final startedAtUtc = _timeForSample(_currentStartSample);
    final path = await _segmentIndex.createSegmentPath(
      startedAtUtc,
      extension: '.wav',
    );
    final writer = await WavSegmentWriter.open(
      path: path,
      sampleRate: config.sampleRate,
      channels: config.channels,
    );
    if (_currentOverlapSamples > 0) {
      await writer.write(_overlapBytes);
    }
    _writer = writer;
    _writerStartedAtUtc = startedAtUtc;
    _writerPath = path;
    _snapshot.add(
      _snapshot.value.copyWith(
        isRecording: true,
        isStarting: false,
        activeSegmentPath: path,
        activeSegmentStartedAtUtc: startedAtUtc,
        error: null,
      ),
    );
  }

  Future<void> _finishActiveSegment() async {
    final config = _config;
    final writer = _writer;
    final path = _writerPath;
    final startedAtUtc = _writerStartedAtUtc;
    if (config == null ||
        writer == null ||
        path == null ||
        startedAtUtc == null) {
      return;
    }
    _writer = null;
    _writerPath = null;
    _writerStartedAtUtc = null;
    if (_currentUniqueSamples <= 0) {
      await writer.cancel();
      return;
    }
    final file = await writer.close();
    final stat = await file.exists() ? await file.stat() : null;
    final endedAtUtc = _timeForSample(
      _currentStartSample + _currentUniqueSamples,
    );
    final segment = RecordingSegment(
      id: SegmentIndex.safeSegmentId(startedAtUtc),
      startedAtUtc: startedAtUtc,
      endedAtUtc: endedAtUtc,
      captureSessionId: _captureSessionId ?? '',
      sequence: _sequence,
      sampleRate: config.sampleRate,
      channels: config.channels,
      startSample: _currentStartSample,
      sampleCount: _currentUniqueSamples,
      storedSampleCount: writer.sampleCount,
      overlapSamples: _currentOverlapSamples,
      container: 'wav',
      codec: 'pcm_s16le',
      localPath: path,
      byteSize: stat?.size ?? 0,
      uploadStatus: SegmentUploadStatus.pending,
    );
    _sequence += 1;
    _currentUniqueSamples = 0;
    _currentOverlapSamples = 0;
    if (segment.byteSize > 0) {
      _closedSegments.add(segment);
    }
  }

  void _rememberOverlap(Uint8List bytes, int overlapSamples, int frameSize) {
    final overlapBytes = overlapSamples * frameSize;
    if (overlapBytes <= 0) {
      _overlapBytes = Uint8List(0);
      return;
    }
    final combined = Uint8List.fromList([..._overlapBytes, ...bytes]);
    if (combined.length <= overlapBytes) {
      _overlapBytes = combined;
      return;
    }
    _overlapBytes = Uint8List.fromList(
      combined.sublist(combined.length - overlapBytes),
    );
  }

  void _detectCommotion(Uint8List bytes, int samples) {
    final config = _config;
    final sessionId = _captureSessionId;
    if (config == null || sessionId == null || bytes.length < 2) {
      return;
    }
    final stats = _pcmPower(bytes);
    // Higher sensitivity (0..1) lowers the loudness thresholds and the time the
    // sound must be sustained before the "commotion" alert fires.
    final sensitivity = config.noiseTriggerSensitivity.clamp(0.0, 1.0);
    final avgThreshold = 0.30 - 0.26 * sensitivity;
    final peakThreshold = 0.95 - 0.55 * sensitivity;
    final loud =
        stats.averagePower >= avgThreshold || stats.peakPower >= peakThreshold;
    if (loud) {
      _commotionSamples += samples;
    } else {
      _commotionSamples = math.max(0, _commotionSamples - samples);
    }
    final sustainSeconds = (5.0 - 4.0 * sensitivity).clamp(1.0, 5.0);
    final sustainedSamples = (config.sampleRate * sustainSeconds).round();
    if (_commotionSamples < sustainedSamples) {
      return;
    }
    final occurredAt = _timeForSample(_totalLiveSamples);
    final lastAlert = _lastCommotionAlertUtc;
    if (lastAlert != null &&
        occurredAt.difference(lastAlert) < const Duration(minutes: 2)) {
      return;
    }
    _lastCommotionAlertUtc = occurredAt;
    _commotionSamples = 0;
    _triggerEvents.add(
      AudioTriggerEvent(
        type: AudioTriggerType.commotion,
        occurredAtUtc: occurredAt,
        captureSessionId: sessionId,
        sampleIndex: _totalLiveSamples,
        averagePower: stats.averagePower,
        peakPower: stats.peakPower,
      ),
    );
  }

  _PcmPower _pcmPower(Uint8List bytes) {
    var sumSquares = 0.0;
    var peak = 0.0;
    var count = 0;
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
      final value = data.getInt16(offset, Endian.little);
      final normalized = value.abs() / 32768.0;
      peak = math.max(peak, normalized);
      sumSquares += normalized * normalized;
      count += 1;
    }
    if (count == 0) {
      return const _PcmPower(averagePower: 0, peakPower: 0);
    }
    return _PcmPower(
      averagePower: math.sqrt(sumSquares / count),
      peakPower: peak,
    );
  }

  DateTime _timeForSample(int sample) {
    final config = _config;
    final captureStartedAt = _captureStartedAtUtc;
    if (config == null || captureStartedAt == null || config.sampleRate <= 0) {
      return DateTime.now().toUtc();
    }
    return captureStartedAt.add(
      Duration(microseconds: sample * 1000000 ~/ config.sampleRate),
    );
  }

  void _completeStreamDone() {
    final done = _streamDone;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }
}

class _PcmPower {
  const _PcmPower({required this.averagePower, required this.peakPower});

  final double averagePower;
  final double peakPower;
}

/// Client-side audio shaping for int16 PCM: a linear input gain followed by an
/// optional 3-band tone control (low shelf / mid peak / high shelf). Filter
/// state is kept per channel across slices so segment boundaries stay seamless.
class _AudioDsp {
  _AudioDsp._(this._gain, this._stages, int channels)
    : _states = List.generate(
        _stages.length,
        (_) => List.generate(channels, (_) => _BiquadState()),
      );

  final double _gain;
  final List<_Biquad> _stages;
  final List<List<_BiquadState>> _states;

  static _AudioDsp? fromConfig(AppConfig config) {
    if (!config.hasAudioDsp) {
      return null;
    }
    final fs = config.sampleRate.toDouble();
    final stages = <_Biquad>[];
    if (config.bassGainDb != 0.0) {
      stages.add(_Biquad.lowShelf(fs, 120, config.bassGainDb));
    }
    if (config.midGainDb != 0.0) {
      stages.add(_Biquad.peaking(fs, 1000, 0.9, config.midGainDb));
    }
    if (config.trebleGainDb != 0.0) {
      stages.add(_Biquad.highShelf(fs, 6000, config.trebleGainDb));
    }
    return _AudioDsp._(config.micSensitivity, stages, config.channels.clamp(1, 2));
  }

  Uint8List process(Uint8List frameBytes, int channels) {
    final out = Uint8List.fromList(frameBytes);
    final view = ByteData.sublistView(out);
    final sampleCount = out.length ~/ 2;
    for (var i = 0; i < sampleCount; i++) {
      final channel = channels <= 1 ? 0 : i % channels;
      var sample = view.getInt16(i * 2, Endian.little) / 32768.0;
      sample *= _gain;
      for (var s = 0; s < _stages.length; s++) {
        sample = _states[s][channel].process(_stages[s], sample);
      }
      var scaled = (sample * 32768.0).round();
      if (scaled > 32767) {
        scaled = 32767;
      } else if (scaled < -32768) {
        scaled = -32768;
      }
      view.setInt16(i * 2, scaled, Endian.little);
    }
    return out;
  }
}

/// Normalized (a0 == 1) biquad coefficients from the RBJ audio EQ cookbook.
class _Biquad {
  const _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  factory _Biquad.peaking(double fs, double f0, double q, double gainDb) {
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * f0 / fs;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final a0 = 1 + alpha / a;
    return _Biquad(
      (1 + alpha * a) / a0,
      (-2 * cosW0) / a0,
      (1 - alpha * a) / a0,
      (-2 * cosW0) / a0,
      (1 - alpha / a) / a0,
    );
  }

  factory _Biquad.lowShelf(double fs, double f0, double gainDb) {
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * f0 / fs;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / 2 * math.sqrt2;
    final twoSqrtAAlpha = 2 * math.sqrt(a) * alpha;
    final a0 = (a + 1) + (a - 1) * cosW0 + twoSqrtAAlpha;
    return _Biquad(
      (a * ((a + 1) - (a - 1) * cosW0 + twoSqrtAAlpha)) / a0,
      (2 * a * ((a - 1) - (a + 1) * cosW0)) / a0,
      (a * ((a + 1) - (a - 1) * cosW0 - twoSqrtAAlpha)) / a0,
      (-2 * ((a - 1) + (a + 1) * cosW0)) / a0,
      ((a + 1) + (a - 1) * cosW0 - twoSqrtAAlpha) / a0,
    );
  }

  factory _Biquad.highShelf(double fs, double f0, double gainDb) {
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * f0 / fs;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / 2 * math.sqrt2;
    final twoSqrtAAlpha = 2 * math.sqrt(a) * alpha;
    final a0 = (a + 1) - (a - 1) * cosW0 + twoSqrtAAlpha;
    return _Biquad(
      (a * ((a + 1) + (a - 1) * cosW0 + twoSqrtAAlpha)) / a0,
      (-2 * a * ((a - 1) + (a + 1) * cosW0)) / a0,
      (a * ((a + 1) + (a - 1) * cosW0 - twoSqrtAAlpha)) / a0,
      (2 * ((a - 1) - (a + 1) * cosW0)) / a0,
      ((a + 1) - (a - 1) * cosW0 - twoSqrtAAlpha) / a0,
    );
  }
}

class _BiquadState {
  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  double process(_Biquad c, double x) {
    final y =
        c.b0 * x + c.b1 * _x1 + c.b2 * _x2 - c.a1 * _y1 - c.a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}
