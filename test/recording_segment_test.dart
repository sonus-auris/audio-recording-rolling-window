import 'package:audio_dashcam/src/models/recording_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses sample metadata for canonical duration and overlap trim', () {
    final startedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final segment = RecordingSegment(
      id: 'segment-1',
      startedAtUtc: startedAt,
      endedAtUtc: startedAt.add(const Duration(minutes: 1)),
      byteSize: 1984044,
      uploadStatus: SegmentUploadStatus.pending,
      sampleRate: 16000,
      channels: 1,
      startSample: 960000,
      sampleCount: 960000,
      storedSampleCount: 992000,
      overlapSamples: 32000,
      container: 'wav',
      codec: 'pcm_s16le',
      localPath: '/tmp/segment.wav',
    );

    expect(segment.hasSampleTimeline, isTrue);
    expect(segment.endSampleExclusive, 1920000);
    expect(segment.storedStartSample, 928000);
    expect(segment.trimStart, const Duration(seconds: 2));
    expect(segment.canonicalDuration, const Duration(minutes: 1));
    expect(segment.fileExtension, 'wav');
    expect(segment.contentType, 'audio/wav');
  });

  test('persists permanent save metadata', () {
    final startedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final savedAt = DateTime.utc(2026, 1, 2, 4);
    final segment = RecordingSegment(
      id: 'segment-1',
      startedAtUtc: startedAt,
      endedAtUtc: startedAt.add(const Duration(minutes: 1)),
      byteSize: 4,
      uploadStatus: SegmentUploadStatus.uploaded,
      remoteKey: 'rolling/segment-1.wav',
      permanentRemoteKey: 'permanent/segment-1.wav',
      permanentSavedAtUtc: savedAt,
    );

    final decoded = RecordingSegment.fromJson(segment.toJson());

    expect(decoded.isUploaded, isTrue);
    expect(decoded.isPermanentlySaved, isTrue);
    expect(decoded.permanentRemoteKey, 'permanent/segment-1.wav');
    expect(decoded.permanentSavedAtUtc, savedAt);
  });
}
