import 'cloud_provider.dart';

class AppConfig {
  const AppConfig({
    required this.deviceId,
    this.deviceRetentionHours = 50,
    this.cloudRetentionHours = 500,
    this.segmentMinutes = 1,
    this.bitRate = 64000,
    this.sampleRate = 16000,
    this.channels = 1,
    this.uploadEnabled = true,
    this.cloudProvider = CloudProvider.s3,
    this.s3Bucket = '',
    this.s3Region = 'us-east-1',
    this.s3Prefix = 'audio-dashcam',
    this.s3Endpoint = '',
  });

  final String deviceId;
  final int deviceRetentionHours;
  final int cloudRetentionHours;
  final int segmentMinutes;
  final int bitRate;
  final int sampleRate;
  final int channels;
  final bool uploadEnabled;
  final CloudProvider cloudProvider;
  final String s3Bucket;
  final String s3Region;
  final String s3Prefix;
  final String s3Endpoint;

  bool get s3TargetReady =>
      s3Bucket.trim().isNotEmpty && s3Region.trim().isNotEmpty;

  Duration get segmentDuration => Duration(minutes: segmentMinutes);

  AppConfig copyWith({
    String? deviceId,
    int? deviceRetentionHours,
    int? cloudRetentionHours,
    int? segmentMinutes,
    int? bitRate,
    int? sampleRate,
    int? channels,
    bool? uploadEnabled,
    CloudProvider? cloudProvider,
    String? s3Bucket,
    String? s3Region,
    String? s3Prefix,
    String? s3Endpoint,
  }) {
    return AppConfig(
      deviceId: deviceId ?? this.deviceId,
      deviceRetentionHours: deviceRetentionHours ?? this.deviceRetentionHours,
      cloudRetentionHours: cloudRetentionHours ?? this.cloudRetentionHours,
      segmentMinutes: segmentMinutes ?? this.segmentMinutes,
      bitRate: bitRate ?? this.bitRate,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      uploadEnabled: uploadEnabled ?? this.uploadEnabled,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      s3Bucket: s3Bucket ?? this.s3Bucket,
      s3Region: s3Region ?? this.s3Region,
      s3Prefix: s3Prefix ?? this.s3Prefix,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceRetentionHours': deviceRetentionHours,
      'cloudRetentionHours': cloudRetentionHours,
      'segmentMinutes': segmentMinutes,
      'bitRate': bitRate,
      'sampleRate': sampleRate,
      'channels': channels,
      'uploadEnabled': uploadEnabled,
      'cloudProvider': cloudProvider.name,
      's3Bucket': s3Bucket,
      's3Region': s3Region,
      's3Prefix': s3Prefix,
      's3Endpoint': s3Endpoint,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      deviceId: json['deviceId'] as String,
      deviceRetentionHours: _asInt(json['deviceRetentionHours'], 50),
      cloudRetentionHours: _asInt(json['cloudRetentionHours'], 500),
      segmentMinutes: _asInt(json['segmentMinutes'], 1).clamp(1, 60),
      bitRate: _asInt(json['bitRate'], 64000),
      sampleRate: _asInt(json['sampleRate'], 16000),
      channels: _asInt(json['channels'], 1).clamp(1, 2),
      uploadEnabled: json['uploadEnabled'] as bool? ?? true,
      cloudProvider: CloudProvider.fromName(json['cloudProvider'] as String?),
      s3Bucket: json['s3Bucket'] as String? ?? '',
      s3Region: json['s3Region'] as String? ?? 'us-east-1',
      s3Prefix: json['s3Prefix'] as String? ?? 'audio-dashcam',
      s3Endpoint: json['s3Endpoint'] as String? ?? '',
    );
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
