import 'package:audio_dashcam/src/models/storage_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimates 500 hours at 64 kbps', () {
    const estimate = StorageEstimate(
      bitRate: 64000,
      deviceHours: 50,
      cloudHours: 500,
    );

    expect(estimate.bytesPerMinute, 480000);
    expect(estimate.deviceBytes, 1440000000);
    expect(estimate.cloudBytes, 14400000000);
    expect(StorageEstimate.formatBytes(estimate.cloudBytes), '14 GB');
  });

  test('estimates 500 hours at 128 kbps', () {
    const estimate = StorageEstimate(
      bitRate: 128000,
      deviceHours: 50,
      cloudHours: 500,
    );

    expect(estimate.cloudBytes, 28800000000);
    expect(StorageEstimate.formatBytes(estimate.cloudBytes), '29 GB');
  });
}
