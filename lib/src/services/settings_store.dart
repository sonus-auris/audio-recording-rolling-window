import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_config.dart';
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
  static const _s3AccessKeyKey = 'audio_dashcam.s3.access_key_id';
  static const _s3SecretKeyKey = 'audio_dashcam.s3.secret_access_key';
  static const _s3SessionTokenKey = 'audio_dashcam.s3.session_token';

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

  Future<CloudSecrets> loadSecrets() async {
    return CloudSecrets(
      s3AccessKeyId: await _secureStorage.read(key: _s3AccessKeyKey) ?? '',
      s3SecretAccessKey: await _secureStorage.read(key: _s3SecretKeyKey) ?? '',
      s3SessionToken: await _secureStorage.read(key: _s3SessionTokenKey) ?? '',
    );
  }

  Future<void> saveSecrets(CloudSecrets secrets) async {
    await _writeSecure(_s3AccessKeyKey, secrets.s3AccessKeyId);
    await _writeSecure(_s3SecretKeyKey, secrets.s3SecretAccessKey);
    await _writeSecure(_s3SessionTokenKey, secrets.s3SessionToken);
  }

  Future<void> _writeSecure(String key, String value) async {
    if (value.trim().isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value.trim());
    }
  }
}
