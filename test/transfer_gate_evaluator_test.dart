import 'package:audio_dashcam/src/models/app_config.dart';
import 'package:audio_dashcam/src/models/transfer_gate_status.dart';
import 'package:audio_dashcam/src/models/upload_network_policy.dart';
import 'package:audio_dashcam/src/services/transfer_gate_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig _config({
  bool pauseOnLowBattery = true,
  int threshold = 20,
  UploadNetworkPolicy policy = UploadNetworkPolicy.any,
}) {
  return AppConfig(
    deviceId: 'device-1',
    pauseUploadsOnLowBattery: pauseOnLowBattery,
    lowBatteryThresholdPercent: threshold,
    uploadNetworkPolicy: policy,
  );
}

void main() {
  group('battery gate', () {
    test('blocks below threshold when discharging', () {
      final status = evaluateTransferGate(
        config: _config(threshold: 20),
        batteryLevel: 18,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isFalse);
      expect(status.reason, TransferBlockReason.lowBattery);
      expect(status.wireReason, 'low_battery');
    });

    test('allows below threshold while charging', () {
      final status = evaluateTransferGate(
        config: _config(threshold: 20),
        batteryLevel: 5,
        isCharging: true,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });

    test('allows at/above threshold (catch-up after recovery)', () {
      final status = evaluateTransferGate(
        config: _config(threshold: 20),
        batteryLevel: 20,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });

    test('battery gate disabled lets a low battery through', () {
      final status = evaluateTransferGate(
        config: _config(pauseOnLowBattery: false, threshold: 20),
        batteryLevel: 2,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });

    test('unknown battery level (-1) fails open', () {
      final status = evaluateTransferGate(
        config: _config(threshold: 20),
        batteryLevel: -1,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });
  });

  group('network policy gate', () {
    test('wifiOnly blocks on cellular', () {
      final status = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.wifiOnly),
        batteryLevel: 90,
        isCharging: false,
        onWifi: false,
        onCellular: true,
        isOnline: true,
      );
      expect(status.allowed, isFalse);
      expect(status.reason, TransferBlockReason.networkPolicy);
      expect(status.wireReason, 'network_constraint');
    });

    test('wifiOnly allows on wifi', () {
      final status = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.wifiOnly),
        batteryLevel: 90,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });

    test('cellularOnly blocks on wifi', () {
      final status = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.cellularOnly),
        batteryLevel: 90,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isFalse);
      expect(status.reason, TransferBlockReason.networkPolicy);
    });

    test('any policy allows either transport', () {
      final wifi = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.any),
        batteryLevel: 90,
        isCharging: false,
        onWifi: true,
        onCellular: false,
        isOnline: true,
      );
      final cell = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.any),
        batteryLevel: 90,
        isCharging: false,
        onWifi: false,
        onCellular: true,
        isOnline: true,
      );
      expect(wifi.allowed, isTrue);
      expect(cell.allowed, isTrue);
    });

    test('unknown transport fails open under a restrictive policy', () {
      final status = evaluateTransferGate(
        config: _config(policy: UploadNetworkPolicy.wifiOnly),
        batteryLevel: 90,
        isCharging: false,
        onWifi: false,
        onCellular: false,
        isOnline: true,
      );
      expect(status.allowed, isTrue);
    });
  });

  test('offline blocks regardless of other conditions', () {
    final status = evaluateTransferGate(
      config: _config(),
      batteryLevel: 100,
      isCharging: true,
      onWifi: false,
      onCellular: false,
      isOnline: false,
    );
    expect(status.allowed, isFalse);
    expect(status.reason, TransferBlockReason.offline);
  });

  test('battery gate takes priority over network policy', () {
    final status = evaluateTransferGate(
      config: _config(threshold: 20, policy: UploadNetworkPolicy.wifiOnly),
      batteryLevel: 10,
      isCharging: false,
      onWifi: false,
      onCellular: true,
      isOnline: true,
    );
    expect(status.reason, TransferBlockReason.lowBattery);
  });
}
