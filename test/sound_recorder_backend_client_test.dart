import 'dart:convert';
import 'dart:io';

import 'package:audio_dashcam/src/models/app_config.dart';
import 'package:audio_dashcam/src/models/cloud_secrets.dart';
import 'package:audio_dashcam/src/models/recording_segment.dart';
import 'package:audio_dashcam/src/services/sound_recorder_backend_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;
  late File segmentFile;
  late RecordingSegment segment;

  const config = AppConfig(
    deviceId: 'device-a',
    backendBaseUrl: 'https://backend.example',
  );
  const secrets = CloudSecrets(backendDeviceToken: 'device-token');
  const session = BackendUploadSession(
    id: 'session-1',
    expiresAtUtc: null,
    maxSegmentBytes: 10 * 1024 * 1024,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'audio_dashcam_backend_test_',
    );
    segmentFile = File('${tempDir.path}/segment.wav');
    await segmentFile.writeAsBytes(const [0, 0, 1, 0]);
    final startedAtUtc = DateTime.utc(2026, 1, 2, 3, 4, 5);
    segment = RecordingSegment(
      id: 'segment-1',
      startedAtUtc: startedAtUtc,
      endedAtUtc: startedAtUtc.add(const Duration(minutes: 1)),
      localPath: segmentFile.path,
      byteSize: 4,
      uploadStatus: SegmentUploadStatus.pending,
      container: 'wav',
      codec: 'pcm_s16le',
      sampleRate: 16000,
      channels: 1,
      sampleCount: 960000,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects signed upload methods other than PUT', () async {
    final client = SoundRecorderBackendClient(
      httpClient: _presignOnlyClient(
        upload: {
          'method': 'POST',
          'url': 'https://uploads.example/segment.wav',
          'headers': <Object>[],
        },
      ),
    );

    final result = await client.uploadSegment(
      config: config,
      secrets: secrets,
      session: session,
      segment: segment,
      file: segmentFile,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('PUT'));
    client.close();
  });

  test('rejects non-HTTPS signed upload URLs', () async {
    final client = SoundRecorderBackendClient(
      httpClient: _presignOnlyClient(
        upload: {
          'method': 'PUT',
          'url': 'http://uploads.example/segment.wav',
          'headers': <Object>[],
        },
      ),
    );

    final result = await client.uploadSegment(
      config: config,
      secrets: secrets,
      session: session,
      segment: segment,
      file: segmentFile,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('HTTPS'));
    client.close();
  });

  test('rejects forbidden signed upload headers', () async {
    final client = SoundRecorderBackendClient(
      httpClient: _presignOnlyClient(
        upload: {
          'method': 'PUT',
          'url': 'https://uploads.example/segment.wav',
          'headers': [
            {'name': 'Authorization', 'value': 'Bearer not-allowed'},
          ],
        },
      ),
    );

    final result = await client.uploadSegment(
      config: config,
      secrets: secrets,
      session: session,
      segment: segment,
      file: segmentFile,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('not allowed'));
    client.close();
  });

  test('returns an alert error for unsafe backend URLs', () async {
    final client = SoundRecorderBackendClient(
      httpClient: MockClient((_) async {
        fail('unsafe backend URL should fail before an HTTP request is sent');
      }),
    );

    final error = await client.postAlert(
      config: const AppConfig(
        deviceId: 'device-a',
        backendBaseUrl: 'http://backend.example',
      ),
      secrets: secrets,
      trigger: 'manual',
      occurredAtUtc: DateTime.utc(2026, 1, 2, 3, 4, 5),
      segmentId: 'segment-1',
      sequence: 1,
    );

    expect(error, contains('HTTPS'));
    client.close();
  });
}

MockClient _presignOnlyClient({required Map<String, Object?> upload}) {
  return MockClient((request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/presign')) {
      return http.Response(
        jsonEncode({
          'upload': upload,
          'segment': {
            'id': 'server-segment-1',
            'storageKey': 'audio-dashcam/device-a/segment.wav',
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    fail('unexpected request: ${request.method} ${request.url}');
  });
}
