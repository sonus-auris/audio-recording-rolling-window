import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/acoustic_detection.dart';
import 'acoustic/acoustic_pipeline.dart';

/// Runs the FFT [AcousticPipeline] on a background isolate so the audio capture
/// path never blocks on analysis. The main isolate slices the decimated mono
/// stream into frames ([FrameSlicer]) and ships them over; detections come back
/// on [detections].
///
/// Lifecycle mirrors the other services: [start] once per capture session,
/// [addMonoSamples] as audio flows, [flush] when the analysis gate closes, then
/// [stop]/[dispose].
class AcousticAnalyzer {
  AcousticAnalyzer();

  final StreamController<AcousticDetection> _detections =
      StreamController<AcousticDetection>.broadcast();

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _receivePort;
  FrameSlicer? _slicer;
  Future<void>? _starting;
  bool _disposed = false;

  Stream<AcousticDetection> get detections => _detections.stream;

  bool get isRunning => _commandPort != null;

  Future<void> start({
    required int sampleRate,
    required int fftSize,
    required AcousticDetectorFlags flags,
    String captureSessionId = '',
  }) async {
    if (_disposed || !flags.any) {
      return;
    }
    await stop();
    _slicer = FrameSlicer(fftSize: fftSize, sampleRate: sampleRate);
    final ready = Completer<SendPort>();
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is List && message.isNotEmpty && message[0] == 'detections') {
        final rows = message[1] as List;
        for (final row in rows) {
          if (_detections.isClosed) {
            break;
          }
          _detections.add(
            AcousticDetection.fromJson((row as Map).cast<String, dynamic>()),
          );
        }
      }
    });
    final starting = Isolate.spawn(_analyzerEntryPoint, {
      'reply': receivePort.sendPort,
      'fftSize': fftSize,
      'sampleRate': sampleRate,
      'flags': flags.toMap(),
      'captureSessionId': captureSessionId,
    }).then((isolate) async {
      _isolate = isolate;
      _commandPort = await ready.future;
    });
    _starting = starting;
    await starting;
  }

  /// Slices [samples] (mono, normalized -1..1, at the analyzer sample rate)
  /// starting at [chunkStartUtc] into frames and dispatches them to the isolate.
  void addMonoSamples(Float64List samples, DateTime chunkStartUtc) {
    final port = _commandPort;
    final slicer = _slicer;
    if (port == null || slicer == null || samples.isEmpty) {
      return;
    }
    for (final framed in slicer.add(samples, chunkStartUtc)) {
      port.send([
        'frame',
        framed.frame,
        framed.atUtc.toUtc().microsecondsSinceEpoch,
      ]);
    }
  }

  /// Asks the isolate to close any open episode (e.g. when the loudness gate
  /// closes); resulting detections arrive on [detections].
  void flush() {
    _commandPort?.send(const ['flush']);
  }

  Future<void> stop() async {
    final starting = _starting;
    if (starting != null) {
      await starting;
    }
    _commandPort?.send(const ['stop']);
    _commandPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _slicer?.reset();
    _slicer = null;
    _starting = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _detections.close();
  }
}

/// Isolate entry point. Owns the [AcousticPipeline] and its detector state for
/// the lifetime of one capture session.
void _analyzerEntryPoint(Map<String, dynamic> args) {
  final reply = args['reply'] as SendPort;
  final pipeline = AcousticPipeline(
    fftSize: args['fftSize'] as int,
    sampleRate: args['sampleRate'] as int,
    flags: AcousticDetectorFlags.fromMap(args['flags'] as Map),
    captureSessionId: args['captureSessionId'] as String? ?? '',
  );
  final commandPort = ReceivePort();
  reply.send(commandPort.sendPort);
  commandPort.listen((message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    switch (message[0]) {
      case 'frame':
        final frame = message[1] as Float64List;
        final atUtc = DateTime.fromMicrosecondsSinceEpoch(
          message[2] as int,
          isUtc: true,
        );
        final detections = pipeline.process(frame, atUtc);
        if (detections.isNotEmpty) {
          reply.send(['detections', detections.map((d) => d.toJson()).toList()]);
        }
        break;
      case 'flush':
        final detections = pipeline.flush();
        if (detections.isNotEmpty) {
          reply.send(['detections', detections.map((d) => d.toJson()).toList()]);
        }
        break;
      case 'stop':
        commandPort.close();
        break;
    }
  });
}
