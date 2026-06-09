import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_config.dart';
import '../models/audio_trigger_event.dart';
import '../models/cloud_secrets.dart';

class SettingsStore {
  SettingsStore({FlutterSecureStorage? secureStorage, Uuid? uuid})
    : _secureStorage = secureStorage ?? _defaultSecureStorage,
      _uuid = uuid ?? const Uuid();

  static const _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );

  static const _configKey = 'audio_dashcam.config.v1';
  static const _pendingAlertsKey = 'audio_dashcam.pending_alerts.v1';
  static const _s3AccessKeyKey = 'audio_dashcam.s3.access_key_id';
  static const _s3SecretKeyKey = 'audio_dashcam.s3.secret_access_key';
  static const _s3SessionTokenKey = 'audio_dashcam.s3.session_token';
  static const _backendDeviceTokenKey = 'audio_dashcam.backend.device_token';
  static const _supabaseAccessTokenKey = 'audio_dashcam.supabase.access_token';

  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;

  Future<AppConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null) {
      final config = AppConfig(deviceId: _uuid.v4());
      await saveConfig(config);
      return config;
    }
    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      final config = AppConfig(deviceId: _uuid.v4());
      await saveConfig(config);
      return config;
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<List<AudioTriggerEvent>> loadPendingAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingAlertsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map(AudioTriggerEvent.fromJson)
          .toList();
    } catch (_) {
      await prefs.remove(_pendingAlertsKey);
      return const [];
    }
  }

  Future<void> savePendingAlerts(List<AudioTriggerEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    if (events.isEmpty) {
      await prefs.remove(_pendingAlertsKey);
      return;
    }
    await prefs.setString(
      _pendingAlertsKey,
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }

  Future<CloudSecrets> loadSecrets() async {
    return CloudSecrets(
      s3AccessKeyId: await _secureStorage.read(key: _s3AccessKeyKey) ?? '',
      s3SecretAccessKey: await _secureStorage.read(key: _s3SecretKeyKey) ?? '',
      s3SessionToken: await _secureStorage.read(key: _s3SessionTokenKey) ?? '',
      backendDeviceToken:
          await _secureStorage.read(key: _backendDeviceTokenKey) ?? '',
      supabaseAccessToken:
          await _secureStorage.read(key: _supabaseAccessTokenKey) ?? '',
    );
  }

  Future<void> saveSecrets(CloudSecrets secrets) async {
    await _writeSecure(_s3AccessKeyKey, secrets.s3AccessKeyId);
    await _writeSecure(_s3SecretKeyKey, secrets.s3SecretAccessKey);
    await _writeSecure(_s3SessionTokenKey, secrets.s3SessionToken);
    await _writeSecure(_backendDeviceTokenKey, secrets.backendDeviceToken);
    await _writeSecure(_supabaseAccessTokenKey, secrets.supabaseAccessToken);
  }

  Future<void> _writeSecure(String key, String value) async {
    if (value.trim().isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value.trim());
    }
  }
}
