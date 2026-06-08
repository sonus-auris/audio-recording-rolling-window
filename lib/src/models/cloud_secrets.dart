class CloudSecrets {
  const CloudSecrets({
    this.s3AccessKeyId = '',
    this.s3SecretAccessKey = '',
    this.s3SessionToken = '',
    this.backendDeviceToken = '',
  });

  final String s3AccessKeyId;
  final String s3SecretAccessKey;
  final String s3SessionToken;
  final String backendDeviceToken;

  bool get hasS3Credentials =>
      s3AccessKeyId.trim().isNotEmpty && s3SecretAccessKey.trim().isNotEmpty;

  bool get hasBackendDeviceToken => backendDeviceToken.trim().isNotEmpty;

  CloudSecrets copyWith({
    String? s3AccessKeyId,
    String? s3SecretAccessKey,
    String? s3SessionToken,
    String? backendDeviceToken,
  }) {
    return CloudSecrets(
      s3AccessKeyId: s3AccessKeyId ?? this.s3AccessKeyId,
      s3SecretAccessKey: s3SecretAccessKey ?? this.s3SecretAccessKey,
      s3SessionToken: s3SessionToken ?? this.s3SessionToken,
      backendDeviceToken: backendDeviceToken ?? this.backendDeviceToken,
    );
  }
}
