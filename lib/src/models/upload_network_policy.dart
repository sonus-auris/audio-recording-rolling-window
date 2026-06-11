/// Which network transports the app is allowed to use when streaming segments
/// to cloud storage. This gates device-originated transfers (direct S3, the
/// backend signed-URL PUT, and client-managed iCloud mirroring) and is also
/// reported to the backend so server-managed copies stay consistent.
enum UploadNetworkPolicy {
  /// Upload over any connection (Wi-Fi or cellular). Default.
  any,

  /// Upload only while on Wi-Fi; defer on cellular.
  wifiOnly,

  /// Upload only while on cellular; defer on Wi-Fi.
  cellularOnly;

  String get label {
    switch (this) {
      case UploadNetworkPolicy.any:
        return 'Wi-Fi or cellular';
      case UploadNetworkPolicy.wifiOnly:
        return 'Wi-Fi only';
      case UploadNetworkPolicy.cellularOnly:
        return 'Cellular only';
    }
  }

  /// Canonical token persisted locally and sent to the backend.
  String get wireName {
    switch (this) {
      case UploadNetworkPolicy.any:
        return 'any';
      case UploadNetworkPolicy.wifiOnly:
        return 'wifi_only';
      case UploadNetworkPolicy.cellularOnly:
        return 'cellular_only';
    }
  }

  static UploadNetworkPolicy fromName(String? name) {
    switch (name) {
      case 'wifi_only':
      case 'wifiOnly':
        return UploadNetworkPolicy.wifiOnly;
      case 'cellular_only':
      case 'cellularOnly':
        return UploadNetworkPolicy.cellularOnly;
      default:
        return UploadNetworkPolicy.any;
    }
  }
}
