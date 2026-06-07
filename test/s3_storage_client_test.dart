import 'dart:io';

import 'package:audio_dashcam/src/models/app_config.dart';
import 'package:audio_dashcam/src/models/cloud_secrets.dart';
import 'package:audio_dashcam/src/models/recording_segment.dart';
import 'package:audio_dashcam/src/services/s3_storage_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File segmentFile;
  late RecordingSegment segment;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_dashcam_s3_test_');
    segmentFile = File('${tempDir.path}/segment.m4a');
    await segmentFile.writeAsBytes(const [1, 2, 3, 4]);
    final startedAtUtc = DateTime.utc(2026, 1, 2, 3, 4, 5);
    segment = RecordingSegment(
      id: '2026-01-02T03-04-05-000z',
      startedAtUtc: startedAtUtc,
      endedAtUtc: startedAtUtc.add(const Duration(minutes: 1)),
      localPath: segmentFile.path,
      byteSize: 4,
      uploadStatus: SegmentUploadStatus.pending,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects non-HTTPS custom endpoints before upload', () async {
    final client = S3StorageClient();
    final result = await client.uploadSegment(
      config: const AppConfig(
        deviceId: 'device-a',
        s3Bucket: 'bucket-a',
        s3Region: 'us-east-1',
        s3Endpoint: 'http://example.com',
      ),
      secrets: const CloudSecrets(
        s3AccessKeyId: 'access',
        s3SecretAccessKey: 'secret',
      ),
      segment: segment,
      file: segmentFile,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('HTTPS'));
    client.close();
  });

  test('rejects invalid direct AWS bucket names before upload', () async {
    final client = S3StorageClient();
    final result = await client.uploadSegment(
      config: const AppConfig(
        deviceId: 'device-a',
        s3Bucket: 'Bad_Bucket',
        s3Region: 'us-east-1',
      ),
      secrets: const CloudSecrets(
        s3AccessKeyId: 'access',
        s3SecretAccessKey: 'secret',
      ),
      segment: segment,
      file: segmentFile,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('lowercase'));
    client.close();
  });
}
