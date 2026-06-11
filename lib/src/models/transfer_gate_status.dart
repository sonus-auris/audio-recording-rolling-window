/// Why uploads are blocked when a gate denies a transfer. `manual` is reserved
/// for an explicit user pause; `none` means uploads are allowed.
enum TransferBlockReason { none, lowBattery, networkPolicy, offline, manual }

/// A snapshot of the device power/network conditions and whether they currently
/// permit streaming segments to the cloud. Surfaced in the UI and reported to
/// the backend so server-managed copies can stay consistent.
class TransferGateStatus {
  const TransferGateStatus({
    required this.allowed,
    required this.reason,
    required this.batteryLevel,
    required this.isCharging,
    required this.onWifi,
    required this.onCellular,
    required this.isOnline,
    this.detail,
  });

  const TransferGateStatus.unknown()
    : allowed = true,
      reason = TransferBlockReason.none,
      batteryLevel = -1,
      isCharging = false,
      onWifi = false,
      onCellular = false,
      isOnline = true,
      detail = null;

  final bool allowed;
  final TransferBlockReason reason;

  /// 0..100, or -1 when the platform did not report a level.
  final int batteryLevel;
  final bool isCharging;
  final bool onWifi;
  final bool onCellular;
  final bool isOnline;

  /// Human-readable explanation, e.g. "Battery 18% (below 20%)".
  final String? detail;

  bool get isPaused => !allowed;

  /// Canonical reason token reported to the backend (null when allowed).
  String? get wireReason {
    switch (reason) {
      case TransferBlockReason.none:
        return null;
      case TransferBlockReason.lowBattery:
        return 'low_battery';
      case TransferBlockReason.networkPolicy:
        return 'network_constraint';
      case TransferBlockReason.offline:
        return 'offline';
      case TransferBlockReason.manual:
        return 'manual';
    }
  }
}
