import 'dart:io';
import 'dart:typed_data';

import 'package:audio_dashcam/src/services/wav_segment_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_dashcam_wav_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes a playable PCM16 WAV header', () async {
    final path = '${tempDir.path}/segment.wav';
    final writer = await WavSegmentWriter.open(
      path: path,
      sampleRate: 16000,
      channels: 1,
    );
    await writer.write(Uint8List.fromList([0, 0, 255, 127]));
    final file = await writer.close();
    final bytes = await file.readAsBytes();
    final header = ByteData.sublistView(Uint8List.fromList(bytes));

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    expect(header.getUint32(40, Endian.little), 4);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(22, Endian.little), 1);
    expect(writer.sampleCount, 2);
  });
}
