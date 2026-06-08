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
}
