import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/cloud_secrets.dart';
import '../models/recording_segment.dart';

class BackendUploadSession {
  const BackendUploadSession({
    required this.id,
    required this.expiresAtUtc,
    required this.maxSegmentBytes,
  });

  final String id;
  final DateTime? expiresAtUtc;
  final int maxSegmentBytes;

  bool get isUsable {
    final expiresAt = expiresAtUtc;
    if (expiresAt == null) {
      return true;
    }
    return DateTime.now().toUtc().isBefore(
      expiresAt.subtract(const Duration(minutes: 2)),
    );
  }
}

class BackendUploadResult {
  const BackendUploadResult.success(this.remoteKey)
    : error = null,
      session = null;

  const BackendUploadResult.failure(this.error)
    : remoteKey = null,
      session = null;

  const BackendUploadResult.sessionExpired()
    : remoteKey = null,
      error = 'Backend upload session expired.',
      session = null;

  const BackendUploadResult.withSession({
    required this.remoteKey,
    required this.session,
  }) : error = null;

  final String? remoteKey;
  final String? error;
  final BackendUploadSession? session;

  bool get isSuccess => remoteKey != null;
}

class SoundRecorderBackendClient {
  SoundRecorderBackendClient({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 45),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration requestTimeout;

  Future<BackendUploadSession> createUploadSession({
    required AppConfig config,
    required CloudSecrets secrets,
  }) async {
    final uri = _apiUri(config, '/api/mobile/v1/upload-sessions');
    final response = await _httpClient
        .post(
          uri,
          headers: _jsonHeaders(secrets),
          body: jsonEncode({
            'contentType': 'audio/wav',
            'codec': 'pcm_s16le',
            'sampleRate': config.sampleRate,
            'channelCount': config.channels,
            'segmentDurationSeconds': config.segmentDuration.inSeconds,
            'maxSegmentBytes': _maxSegmentBytes(config),
            'metaData': {
              'overlapSeconds': config.overlapSeconds,
              'overlapSamples': config.overlapSamples,
              'captureMode': 'continuous_pcm_stream',
            },
          }),
        )
        .timeout(requestTimeout);
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(body, 'Backend session failed.'));
    }
    final session = body['session'] as Map<String, dynamic>;
    return BackendUploadSession(
      id: session['id'] as String,
      expiresAtUtc: _dateTime(session['expiresAt']),
      maxSegmentBytes: _asInt(session['maxSegmentBytes']),
    );
  }

  Future<BackendUploadResult> uploadSegment({
    required AppConfig config,
    required CloudSecrets secrets,
    required BackendUploadSession session,
    required RecordingSegment segment,
    required File file,
  }) async {
    if (!session.isUsable) {
      return const BackendUploadResult.sessionExpired();
    }
    if (!await file.exists()) {
      return const BackendUploadResult.failure(
        'Local segment file is missing.',
      );
    }
    try {
      final bytes = await file.readAsBytes();
      final sha256Hex = sha256.convert(bytes).toString();
      final presignUri = _apiUri(
        config,
        '/api/mobile/v1/upload-sessions/${session.id}/segments/presign',
      );
      final presignResponse = await _httpClient
          .post(
            presignUri,
            headers: _jsonHeaders(secrets),
            body: jsonEncode({
              'sequenceNumber': segment.sequence,
              'capturedStartedAt': segment.startedAtUtc.toIso8601String(),
              'durationMillis': segment.canonicalDuration.inMilliseconds,
              'contentType': segment.contentType,
              'codec': segment.codec,
              'byteCount': bytes.length,
              'sha256Hex': sha256Hex,
              'metaData': {
                'captureSessionId': segment.captureSessionId,
                'startSample': segment.startSample,
                'sampleCount': segment.sampleCount,
                'storedSampleCount': segment.effectiveStoredSampleCount,
                'overlapSamples': segment.overlapSamples,
                'sampleRate': segment.sampleRate,
                'channels': segment.channels,
              },
            }),
          )
          .timeout(requestTimeout);
      final presignBody = _decode(presignResponse);
      if (presignResponse.statusCode < 200 ||
          presignResponse.statusCode >= 300) {
        return BackendUploadResult.failure(
          _errorMessage(presignBody, 'Backend presign failed.'),
        );
      }
      final upload = presignBody['upload'] as Map<String, dynamic>;
      final serverSegment = presignBody['segment'] as Map<String, dynamic>;
      final uploadUri = _signedUploadUri(upload);
      final uploadResponse = await _httpClient
          .put(uploadUri, headers: _signedTransferHeaders(upload), body: bytes)
          .timeout(requestTimeout);
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        return BackendUploadResult.failure(
          'Signed upload failed: HTTP ${uploadResponse.statusCode} ${uploadResponse.reasonPhrase ?? ''}'
              .trim(),
        );
      }
      final segmentId = serverSegment['id'] as String;
      final completeUri = _apiUri(
        config,
        '/api/mobile/v1/upload-sessions/${session.id}/segments/$segmentId/complete',
      );
      final completeResponse = await _httpClient
          .post(
            completeUri,
            headers: _jsonHeaders(secrets),
            body: jsonEncode({
              'etag': uploadResponse.headers['etag'],
              'byteCount': bytes.length,
              'sha256Hex': sha256Hex,
              'capturedEndedAt': segment.endedAtUtc.toIso8601String(),
            }),
          )
          .timeout(requestTimeout);
      final completeBody = _decode(completeResponse);
      if (completeResponse.statusCode < 200 ||
          completeResponse.statusCode >= 300) {
        return BackendUploadResult.failure(
          _errorMessage(completeBody, 'Backend completion failed.'),
        );
      }
      final completedSegment =
          completeBody['segment'] as Map<String, dynamic>? ?? serverSegment;
      final remoteKey = completedSegment['storageKey'] as String?;
      if (remoteKey == null || remoteKey.trim().isEmpty) {
        return const BackendUploadResult.failure(
          'Backend completion did not return a storage key.',
        );
      }
      return BackendUploadResult.withSession(
        remoteKey: remoteKey,
        session: session,
      );
    } on TimeoutException {
      return BackendUploadResult.failure(
        'Backend upload timed out after ${requestTimeout.inSeconds} seconds.',
      );
    } catch (error) {
      return BackendUploadResult.failure('Backend upload failed: $error');
    }
  }

  Future<String?> postAlert({
    required AppConfig config,
    required CloudSecrets secrets,
    required String trigger,
    required DateTime occurredAtUtc,
    required String? segmentId,
    required int? sequence,
    Map<String, Object?> metadata = const {},
  }) async {
    try {
      final uri = _apiUri(config, '/api/mobile/v1/alerts');
      final response = await _httpClient
          .post(
            uri,
            headers: _jsonHeaders(secrets),
            body: jsonEncode({
              'trigger': trigger,
              'occurredAt': occurredAtUtc.toIso8601String(),
              'listenOffsetSeconds': 20,
              'segmentId': segmentId,
              'sequenceNumber': sequence,
              'metaData': metadata,
            }),
          )
          .timeout(requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      return _errorMessage(_decode(response), 'Alert request failed.');
    } catch (error) {
      return 'Alert request failed: $error';
    }
  }

  bool canUseBackend(AppConfig config, CloudSecrets secrets) {
    return config.backendBaseUrl.trim().isNotEmpty &&
        secrets.hasBackendDeviceToken;
  }

  Uri _apiUri(AppConfig config, String path) {
    final base = Uri.parse(config.backendBaseUrl.trim());
    if (base.host.trim().isEmpty) {
      throw const FormatException('Backend URL must include a host.');
    }
    if (base.scheme != 'https' &&
        base.host != 'localhost' &&
        base.host != '127.0.0.1') {
      throw const FormatException(
        'Backend URL must use HTTPS except localhost development.',
      );
    }
    final baseSegments = base.pathSegments.where((part) => part.isNotEmpty);
    return base.replace(
      pathSegments: [
        ...baseSegments,
        ...path.split('/').where((p) => p.isNotEmpty),
      ],
      query: '',
      fragment: '',
    );
  }

  Map<String, String> _jsonHeaders(CloudSecrets secrets) {
    return {
      'authorization': 'Bearer ${secrets.backendDeviceToken.trim()}',
      'content-type': 'application/json',
      'accept': 'application/json',
    };
  }

  Map<String, String> _signedTransferHeaders(Map<String, dynamic> upload) {
    final headers = <String, String>{};
    for (final header in upload['headers'] as List<dynamic>? ?? const []) {
      final item = header as Map<String, dynamic>;
      final name = (item['name'] as String).trim();
      final value = item['value'] as String;
      final lowerName = name.toLowerCase();
      const forbiddenHeaders = {
        'authorization',
        'cookie',
        'host',
        'content-length',
        'transfer-encoding',
      };
      if (name.isEmpty ||
          name.contains(':') ||
          name.contains('\r') ||
          name.contains('\n') ||
          value.contains('\r') ||
          value.contains('\n') ||
          forbiddenHeaders.contains(lowerName)) {
        throw FormatException('Signed upload header is not allowed: $name.');
      }
      headers[name] = value;
    }
    return headers;
  }

  Uri _signedUploadUri(Map<String, dynamic> upload) {
    final method = upload['method']?.toString().toUpperCase();
    if (method != 'PUT') {
      throw FormatException('Signed upload method must be PUT, got $method.');
    }
    final uri = Uri.parse(upload['url'] as String);
    if (uri.host.trim().isEmpty) {
      throw const FormatException('Signed upload URL must include a host.');
    }
    if (uri.scheme != 'https' &&
        uri.host != 'localhost' &&
        uri.host != '127.0.0.1') {
      throw const FormatException(
        'Signed upload URL must use HTTPS except localhost development.',
      );
    }
    return uri;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const {};
    }
    final value = jsonDecode(response.body);
    return value is Map<String, dynamic> ? value : const {};
  }

  String _errorMessage(Map<String, dynamic> body, String fallback) {
    final message = body['message'] ?? body['error'];
    return message?.toString() ?? fallback;
  }

  DateTime? _dateTime(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _maxSegmentBytes(AppConfig config) {
    final bytesPerSecond = config.effectiveBitRate ~/ 8;
    final seconds = config.segmentDuration.inSeconds + config.overlapSeconds;
    return bytesPerSecond * seconds + 44 + 4096;
  }

  void close() {
    _httpClient.close();
  }
}
