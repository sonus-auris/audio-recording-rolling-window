import 'cloud_provider.dart';

class AppConfig {
  const AppConfig({
    required this.deviceId,
    this.deviceRetentionHours = 50,
    this.cloudRetentionHours = 500,
    this.segmentMinutes = 1,
    this.overlapSeconds = 2,
    this.bitRate = 64000,
    this.sampleRate = 16000,
    this.channels = 1,
    this.uploadEnabled = false,
    this.cloudProvider = CloudProvider.s3,
    this.backendBaseUrl = '',
    this.s3Bucket = '',
    this.s3Region = 'us-east-1',
    this.s3Prefix = 'audio-dashcam',
    this.s3Endpoint = '',
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.useCase = 'security',
    this.micSensitivity = 1.0,
    this.noiseTriggerSensitivity = 0.5,
    this.bassGainDb = 0.0,
    this.midGainDb = 0.0,
    this.trebleGainDb = 0.0,
    this.autoGain = true,
    this.noiseSuppress = true,
    this.verbalCuesEnabled = false,
  });

  /// Capture intents understood by both the app and the backend. Music turns off
  /// the speech-oriented DSP so dynamics and frequency content are preserved.
  static const List<String> supportedUseCases = [
    'security',
    'music',
    'meeting',
    'voice_note',
    'ambient',
  ];

  final String deviceId;
  final int deviceRetentionHours;
  final int cloudRetentionHours;
  final int segmentMinutes;
  final int overlapSeconds;
  final int bitRate;
  final int sampleRate;
  final int channels;
  final bool uploadEnabled;
  final CloudProvider cloudProvider;
  final String backendBaseUrl;
  final String s3Bucket;
  final String s3Region;
  final String s3Prefix;
  final String s3Endpoint;

  /// Supabase project URL (e.g. https://abc.supabase.co). Used for GoTrue
  /// email/password sign-in. Non-secret.
  final String supabaseUrl;

  /// Supabase anon/publishable API key. Safe to ship in the client; never the
  /// service_role or secret key.
  final String supabaseAnonKey;

  /// One of [supportedUseCases].
  final String useCase;

  /// Linear input gain applied to captured PCM (0.25x..4x). 1.0 is unity.
  final double micSensitivity;

  /// Loudness-trigger sensitivity in 0..1; higher fires the "commotion" alert on
  /// quieter sound. Maps to RMS/peak thresholds in the recorder.
  final double noiseTriggerSensitivity;

  /// Tone controls in dB (-12..+12) applied as low/mid/high shelving+peak gain.
  final double bassGainDb;
  final double midGainDb;
  final double trebleGainDb;

  /// Platform auto-gain control. Off by default for music to keep dynamics.
  final bool autoGain;

  /// Platform noise suppression. Off by default for music.
  final bool noiseSuppress;

  /// Speak short confirmations ("recording", "saved") while capturing.
  final bool verbalCuesEnabled;

  bool get isMusic => useCase == 'music';

  bool get hasToneAdjustment =>
      bassGainDb != 0.0 || midGainDb != 0.0 || trebleGainDb != 0.0;

  /// Whether any client-side DSP must run on the PCM stream.
  bool get hasAudioDsp => micSensitivity != 1.0 || hasToneAdjustment;

  /// Snapshot of the audio tuning, mirrored to the backend session so playback
  /// and audit can reproduce the capture configuration.
  Map<String, Object?> get audioProfile => {
    'useCase': useCase,
    'micSensitivity': micSensitivity,
    'noiseTriggerSensitivity': noiseTriggerSensitivity,
    'bassGainDb': bassGainDb,
    'midGainDb': midGainDb,
    'trebleGainDb': trebleGainDb,
    'autoGain': autoGain,
    'noiseSuppress': noiseSuppress,
  };

  bool get s3TargetReady =>
      s3Bucket.trim().isNotEmpty && s3Region.trim().isNotEmpty;

  /// Whether Supabase email/password sign-in can be attempted.
  bool get hasSupabaseAuthConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  Duration get segmentDuration => Duration(minutes: segmentMinutes);

  int get bitsPerSample => 16;

  int get pcmBitRate => sampleRate * channels * bitsPerSample;

  int get effectiveBitRate => pcmBitRate;

  int get samplesPerSegment =>
      sampleRate * segmentDuration.inSeconds.clamp(1, 86400);

  int get overlapSamples {
    final requested = sampleRate * overlapSeconds.clamp(0, 30);
    return requested.clamp(0, samplesPerSegment ~/ 2);
  }

  AppConfig copyWith({
    String? deviceId,
    int? deviceRetentionHours,
    int? cloudRetentionHours,
    int? segmentMinutes,
    int? overlapSeconds,
    int? bitRate,
    int? sampleRate,
    int? channels,
    bool? uploadEnabled,
    CloudProvider? cloudProvider,
    String? backendBaseUrl,
    String? s3Bucket,
    String? s3Region,
    String? s3Prefix,
    String? s3Endpoint,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? useCase,
    double? micSensitivity,
    double? noiseTriggerSensitivity,
    double? bassGainDb,
    double? midGainDb,
    double? trebleGainDb,
    bool? autoGain,
    bool? noiseSuppress,
    bool? verbalCuesEnabled,
  }) {
    return AppConfig(
      deviceId: deviceId ?? this.deviceId,
      deviceRetentionHours: deviceRetentionHours ?? this.deviceRetentionHours,
      cloudRetentionHours: cloudRetentionHours ?? this.cloudRetentionHours,
      segmentMinutes: segmentMinutes ?? this.segmentMinutes,
      overlapSeconds: overlapSeconds ?? this.overlapSeconds,
      bitRate: bitRate ?? this.bitRate,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      uploadEnabled: uploadEnabled ?? this.uploadEnabled,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
      s3Bucket: s3Bucket ?? this.s3Bucket,
      s3Region: s3Region ?? this.s3Region,
      s3Prefix: s3Prefix ?? this.s3Prefix,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseAnonKey: supabaseAnonKey ?? this.supabaseAnonKey,
      useCase: useCase ?? this.useCase,
      micSensitivity: micSensitivity ?? this.micSensitivity,
      noiseTriggerSensitivity:
          noiseTriggerSensitivity ?? this.noiseTriggerSensitivity,
      bassGainDb: bassGainDb ?? this.bassGainDb,
      midGainDb: midGainDb ?? this.midGainDb,
      trebleGainDb: trebleGainDb ?? this.trebleGainDb,
      autoGain: autoGain ?? this.autoGain,
      noiseSuppress: noiseSuppress ?? this.noiseSuppress,
      verbalCuesEnabled: verbalCuesEnabled ?? this.verbalCuesEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceRetentionHours': deviceRetentionHours,
      'cloudRetentionHours': cloudRetentionHours,
      'segmentMinutes': segmentMinutes,
      'overlapSeconds': overlapSeconds,
      'bitRate': bitRate,
      'sampleRate': sampleRate,
      'channels': channels,
      'uploadEnabled': uploadEnabled,
      'cloudProvider': cloudProvider.name,
      'backendBaseUrl': backendBaseUrl,
      's3Bucket': s3Bucket,
      's3Region': s3Region,
      's3Prefix': s3Prefix,
      's3Endpoint': s3Endpoint,
      'supabaseUrl': supabaseUrl,
      'supabaseAnonKey': supabaseAnonKey,
      'useCase': useCase,
      'micSensitivity': micSensitivity,
      'noiseTriggerSensitivity': noiseTriggerSensitivity,
      'bassGainDb': bassGainDb,
      'midGainDb': midGainDb,
      'trebleGainDb': trebleGainDb,
      'autoGain': autoGain,
      'noiseSuppress': noiseSuppress,
      'verbalCuesEnabled': verbalCuesEnabled,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final useCase = json['useCase'] as String? ?? 'security';
    return AppConfig(
      deviceId: json['deviceId'] as String,
      deviceRetentionHours: _asInt(json['deviceRetentionHours'], 50),
      cloudRetentionHours: _asInt(json['cloudRetentionHours'], 500),
      segmentMinutes: _asInt(json['segmentMinutes'], 1).clamp(1, 60),
      overlapSeconds: _asInt(json['overlapSeconds'], 2).clamp(0, 30),
      bitRate: _asInt(json['bitRate'], 64000),
      sampleRate: _asInt(json['sampleRate'], 16000),
      channels: _asInt(json['channels'], 1).clamp(1, 2),
      uploadEnabled: json['uploadEnabled'] as bool? ?? false,
      cloudProvider: CloudProvider.fromName(json['cloudProvider'] as String?),
      backendBaseUrl: json['backendBaseUrl'] as String? ?? '',
      s3Bucket: json['s3Bucket'] as String? ?? '',
      s3Region: json['s3Region'] as String? ?? 'us-east-1',
      s3Prefix: json['s3Prefix'] as String? ?? 'audio-dashcam',
      s3Endpoint: json['s3Endpoint'] as String? ?? '',
      supabaseUrl: json['supabaseUrl'] as String? ?? '',
      supabaseAnonKey: json['supabaseAnonKey'] as String? ?? '',
      useCase: supportedUseCases.contains(useCase) ? useCase : 'security',
      micSensitivity: _asDouble(json['micSensitivity'], 1.0).clamp(0.25, 4.0),
      noiseTriggerSensitivity: _asDouble(
        json['noiseTriggerSensitivity'],
        0.5,
      ).clamp(0.0, 1.0),
      bassGainDb: _asDouble(json['bassGainDb'], 0.0).clamp(-12.0, 12.0),
      midGainDb: _asDouble(json['midGainDb'], 0.0).clamp(-12.0, 12.0),
      trebleGainDb: _asDouble(json['trebleGainDb'], 0.0).clamp(-12.0, 12.0),
      autoGain: json['autoGain'] as bool? ?? true,
      noiseSuppress: json['noiseSuppress'] as bool? ?? true,
      verbalCuesEnabled: json['verbalCuesEnabled'] as bool? ?? false,
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

  static double _asDouble(Object? value, double fallback) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
