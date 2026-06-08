import 'package:audio_dashcam/src/models/audio_trigger_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips alert events for persisted pending queue', () {
    final event = AudioTriggerEvent(
      type: AudioTriggerType.magicPhrase,
      occurredAtUtc: DateTime.utc(2026, 1, 2, 3, 4, 5),
      captureSessionId: 'capture-session-1',
      sampleIndex: 123456,
      averagePower: 0.42,
      peakPower: 0.91,
      phrase: 'all dogs go to heaven',
    );

    final restored = AudioTriggerEvent.fromJson(event.toJson());

    expect(restored.type, AudioTriggerType.magicPhrase);
    expect(restored.serverTrigger, 'magic_phrase');
    expect(restored.occurredAtUtc, event.occurredAtUtc);
    expect(restored.captureSessionId, 'capture-session-1');
    expect(restored.sampleIndex, 123456);
    expect(restored.averagePower, 0.42);
    expect(restored.peakPower, 0.91);
    expect(restored.phrase, 'all dogs go to heaven');
  });
}
