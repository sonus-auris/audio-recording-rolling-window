import 'package:audio_dashcam/src/models/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acoustic + adaptive fields round-trip through JSON', () {
    const config = AppConfig(
      deviceId: 'device-1',
      acousticAnalysisEnabled: true,
      analysisActivationDb: -35,
      analysisSustainSeconds: 3,
      analysisHoldSeconds: 60,
      snoreDetectionEnabled: true,
      musicDetectionEnabled: false,
      speechDetectionEnabled: true,
      shazamEnabled: true,
      keywords: ['help', 'fire'],
      sttEnabled: true,
      sttEndpoint: 'https://stt.example/transcribe',
      adaptiveQualityEnabled: true,
      captureSampleRate: 48000,
      quietSampleRate: 16000,
      adaptiveLoudnessDb: -42,
    );
    final restored = AppConfig.fromJson(config.toJson());
    expect(restored.acousticAnalysisEnabled, isTrue);
    expect(restored.analysisActivationDb, -35);
    expect(restored.analysisSustainSeconds, 3);
    expect(restored.analysisHoldSeconds, 60);
    expect(restored.musicDetectionEnabled, isFalse);
    expect(restored.shazamEnabled, isTrue);
    expect(restored.keywords, ['help', 'fire']);
    expect(restored.sttEnabled, isTrue);
    expect(restored.sttEndpoint, 'https://stt.example/transcribe');
    expect(restored.adaptiveQualityEnabled, isTrue);
    expect(restored.captureSampleRate, 48000);
    expect(restored.quietSampleRate, 16000);
    expect(restored.adaptiveLoudnessDb, -42);
  });

  test('defaults keep analysis off and full capture quality', () {
    const config = AppConfig(deviceId: 'd');
    expect(config.acousticAnalysisEnabled, isFalse);
    expect(config.hasAcousticAnalysis, isFalse);
    expect(config.adaptiveQualityEnabled, isFalse);
    // With adaptive quality off, the mic opens at the plain sample rate.
    expect(config.effectiveCaptureSampleRate, config.sampleRate);
  });

  test('capture geometry derives the analyzer rate and decimation', () {
    const config = AppConfig(
      deviceId: 'd',
      adaptiveQualityEnabled: true,
      captureSampleRate: 48000,
    );
    expect(config.effectiveCaptureSampleRate, 48000);
    expect(config.analyzerDecimationFactor, 3);
    expect(config.analyzerSampleRate, 16000);
    // Per-rate segment math uses the capture rate, not the stored sampleRate.
    expect(config.samplesPerSegmentAt(48000), 48000 * 60);
    expect(config.overlapSamplesAt(48000), 48000 * 2);
  });

  test('hasAcousticAnalysis requires the master switch and a detector', () {
    const noDetectors = AppConfig(
      deviceId: 'd',
      acousticAnalysisEnabled: true,
      snoreDetectionEnabled: false,
      musicDetectionEnabled: false,
      speechDetectionEnabled: false,
    );
    expect(noDetectors.hasAcousticAnalysis, isFalse);
    const enabled = AppConfig(
      deviceId: 'd',
      acousticAnalysisEnabled: true,
      snoreDetectionEnabled: true,
      musicDetectionEnabled: false,
      speechDetectionEnabled: false,
    );
    expect(enabled.hasAcousticAnalysis, isTrue);
  });

  test('out-of-range values are clamped on load', () {
    final json = const AppConfig(deviceId: 'd').toJson()
      ..['captureSampleRate'] = 96000
      ..['quietSampleRate'] = 100
      ..['analysisActivationDb'] = 12.0
      ..['analysisSustainSeconds'] = 999.0;
    final config = AppConfig.fromJson(json);
    expect(config.captureSampleRate, 48000);
    expect(config.quietSampleRate, 8000);
    expect(config.analysisActivationDb, 0.0);
    expect(config.analysisSustainSeconds, 30.0);
  });
}
