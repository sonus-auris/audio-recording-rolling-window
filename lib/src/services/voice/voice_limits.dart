/// Hard resource bounds for the voice-command pipeline.
///
/// The pipeline ingests text that originates from an always-on microphone and,
/// on the cloud path, from a network endpoint that must be treated as
/// untrusted. These caps keep a pathological transcript, a hostile resolver
/// response, or a runaway command from turning into unbounded CPU/memory: they
/// bound regex work (ReDoS surface), persisted note size, timer scheduling, and
/// the size of any response we're willing to parse.
class VoiceLimits {
  const VoiceLimits._();

  /// Longest transcript we will normalize / run rules over. Anything longer is
  /// truncated before matching — a single utterance is never this long, so this
  /// only ever clips abuse, not real speech.
  static const int maxTranscriptChars = 2000;

  /// Longest value we keep for any extracted slot.
  static const int maxSlotValueChars = 1000;

  /// Most slots we will accept from a resolver response.
  static const int maxSlots = 32;

  /// Longest note/task body we will persist.
  static const int maxNoteChars = 4000;

  /// Longest timer / focus session, in seconds (24 h). Guards against integer
  /// overflow in duration math and absurd schedules.
  static const int maxTimerSeconds = 24 * 60 * 60;

  /// Most timers that may run concurrently.
  static const int maxActiveTimers = 64;

  /// Largest resolver HTTP response body (bytes) we will read/parse.
  static const int maxResponseBytes = 64 * 1024;

  /// Clamp a model/parser confidence into a safe [0, 1]. Critically, maps
  /// `NaN`/`Infinity` to 0 so a hostile or buggy value can never slip past a
  /// `confidence >= threshold` gate (NaN comparisons are always false).
  static double sanitizeConfidence(double value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return 0;
    }
    return value > 1 ? 1 : value;
  }

  /// Truncate [value] to [max] characters (null-safe, returns '' for null).
  static String clip(String? value, int max) {
    if (value == null) {
      return '';
    }
    return value.length <= max ? value : value.substring(0, max);
  }
}
