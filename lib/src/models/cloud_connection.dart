/// A linked user-owned cloud destination returned by the backend.
class CloudConnection {
  const CloudConnection({
    required this.id,
    required this.provider,
    required this.linkMode,
    required this.status,
    required this.folderPath,
    this.displayName,
    this.providerAccountId,
    this.lastSyncAtUtc,
  });

  final String id;
  final String provider;
  final String linkMode;
  final String status;
  final String folderPath;
  final String? displayName;
  final String? providerAccountId;
  final DateTime? lastSyncAtUtc;

  bool get isClientManaged => linkMode == 'client_managed';

  factory CloudConnection.fromJson(Map<String, dynamic> json) {
    return CloudConnection(
      id: (json['id'] as String? ?? '').trim(),
      provider: (json['provider'] as String? ?? '').trim(),
      linkMode: (json['linkMode'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? '').trim(),
      folderPath: (json['folderPath'] as String? ?? '').trim(),
      displayName: (json['displayName'] as String?)?.trim(),
      providerAccountId: (json['providerAccountId'] as String?)?.trim(),
      lastSyncAtUtc: DateTime.tryParse(
        json['lastSyncAt']?.toString() ?? '',
      )?.toUtc(),
    );
  }
}

/// The result of starting a cloud link (`oauth/start`).
class CloudLinkStart {
  const CloudLinkStart({
    required this.provider,
    required this.linkMode,
    required this.state,
    this.authorizationUrl,
    this.requiredScope,
    this.clientManaged = false,
  });

  final String provider;
  final String linkMode;
  final String state;
  final String? authorizationUrl;
  final String? requiredScope;
  final bool clientManaged;

  factory CloudLinkStart.fromJson(Map<String, dynamic> json) {
    return CloudLinkStart(
      provider: (json['provider'] as String? ?? '').trim(),
      linkMode: (json['linkMode'] as String? ?? '').trim(),
      state: (json['state'] as String? ?? '').trim(),
      authorizationUrl: (json['authorizationUrl'] as String?)?.trim(),
      requiredScope: (json['requiredScope'] as String?)?.trim(),
      clientManaged: json['clientManaged'] as bool? ?? false,
    );
  }
}
