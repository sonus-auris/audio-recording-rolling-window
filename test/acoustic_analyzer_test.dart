import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_dashcam/src/models/acoustic_detection.dart';
import 'package:audio_dashcam/src/services/acoustic/acoustic_pipeline.dart';
import 'package:audio_dashcam/src/services/acoustic_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analyzer isolate emits detections for low-freq snore bursts', () async {
    const sampleRate = 16000;
    const fftSize = 2048;
    final analyzer = AcousticAnalyzer();
    final received = <AcousticDetection>[];
    final sub = analyzer.detections.listen(received.add);

    await analyzer.start(
      sampleRate: sampleRate,
      fftSize: fftSize,
      flags: const AcousticDetectorFlags(
        snore: true,
        music: false,
        speech: false,
      ),
    );

    // 1s of 150 Hz tone, 3s silence, repeated — a snore-like cadence.
    var clock = DateTime.utc(2026, 1, 1, 4, 0, 0);
    void emit(double seconds, double freq, double amp) {
      final n = (seconds * sampleRate).round();
      final samples = Float64List(n);
      for (var i = 0; i < n; i++) {
        samples[i] = amp * math.sin(2 * math.pi * freq * i / sampleRate);
      }
      analyzer.addMonoSamples(samples, clock);
      clock = clock.add(Duration(microseconds: (seconds * 1e6).round()));
    }

    for (var i = 0; i < 4; i++) {
      emit(1.0, 150, 0.5);
      emit(3.0, 0, 0.0);
    }
    analyzer.flush();

    // Give the isolate time to process and report back.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await analyzer.dispose();
    await sub.cancel();

    expect(
      received.where((e) => e.kind == AcousticDetectionKind.snore),
      isNotEmpty,
    );
  });
}
