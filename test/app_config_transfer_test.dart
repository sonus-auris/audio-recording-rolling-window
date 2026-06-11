import 'package:audio_dashcam/src/models/app_config.dart';
import 'package:audio_dashcam/src/models/upload_network_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults: battery saver on at 20%, network policy any', () {
    const config = AppConfig(deviceId: 'd');
    expect(config.pauseUploadsOnLowBattery, isTrue);
    expect(config.lowBatteryThresholdPercent, 20);
    expect(config.uploadNetworkPolicy, UploadNetworkPolicy.any);
  });

  test('round-trips transfer fields through JSON', () {
    const config = AppConfig(
      deviceId: 'd',
      pauseUploadsOnLowBattery: false,
      lowBatteryThresholdPercent: 35,
      uploadNetworkPolicy: UploadNetworkPolicy.wifiOnly,
    );
    final restored = AppConfig.fromJson(config.toJson());
    expect(restored.pauseUploadsOnLowBattery, isFalse);
    expect(restored.lowBatteryThresholdPercent, 35);
    expect(restored.uploadNetworkPolicy, UploadNetworkPolicy.wifiOnly);
  });

  test('persists the canonical wire token for the network policy', () {
    const config = AppConfig(
      deviceId: 'd',
      uploadNetworkPolicy: UploadNetworkPolicy.cellularOnly,
    );
    expect(config.toJson()['uploadNetworkPolicy'], 'cellular_only');
  });

  test('legacy config without transfer fields falls back to safe defaults', () {
    final restored = AppConfig.fromJson(const {'deviceId': 'd'});
    expect(restored.pauseUploadsOnLowBattery, isTrue);
    expect(restored.lowBatteryThresholdPercent, 20);
    expect(restored.uploadNetworkPolicy, UploadNetworkPolicy.any);
  });

  test('clamps an out-of-range stored threshold', () {
    final restored = AppConfig.fromJson(const {
      'deviceId': 'd',
      'lowBatteryThresholdPercent': 500,
    });
    expect(restored.lowBatteryThresholdPercent, 100);
  });
}
