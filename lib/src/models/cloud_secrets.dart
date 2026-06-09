class CloudSecrets {
  const CloudSecrets({
    this.s3AccessKeyId = '',
    this.s3SecretAccessKey = '',
    this.s3SessionToken = '',
    this.backendDeviceToken = '',
    this.supabaseAccessToken = '',
  });

  final String s3AccessKeyId;
  final String s3SecretAccessKey;
  final String s3SessionToken;
  final String backendDeviceToken;

  /// Supabase access-token JWT for the signed-in user. Sent to the backend as
  /// the `x-supabase-auth` identity header for registration and cloud linking.
  /// Never an admin/service key — only the user's session token.
  final String supabaseAccessToken;

  bool get hasS3Credentials =>
      s3AccessKeyId.trim().isNotEmpty && s3SecretAccessKey.trim().isNotEmpty;

  bool get hasBackendDeviceToken => backendDeviceToken.trim().isNotEmpty;

  bool get hasSupabaseToken => supabaseAccessToken.trim().isNotEmpty;

  CloudSecrets copyWith({
    String? s3AccessKeyId,
    String? s3SecretAccessKey,
    String? s3SessionToken,
    String? backendDeviceToken,
    String? supabaseAccessToken,
  }) {
    return CloudSecrets(
      s3AccessKeyId: s3AccessKeyId ?? this.s3AccessKeyId,
      s3SecretAccessKey: s3SecretAccessKey ?? this.s3SecretAccessKey,
      s3SessionToken: s3SessionToken ?? this.s3SessionToken,
      backendDeviceToken: backendDeviceToken ?? this.backendDeviceToken,
      supabaseAccessToken: supabaseAccessToken ?? this.supabaseAccessToken,
    );
  }
}
