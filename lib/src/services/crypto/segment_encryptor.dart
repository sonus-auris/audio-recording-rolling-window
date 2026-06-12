import 'dart:typed_data';

import 'key_manager.dart';
import 'segment_cipher.dart';

/// Thin facade the upload/download paths depend on, so they never touch key
/// material directly. Seals plaintext audio into a [SegmentCipher] container
/// before it leaves the device, and opens containers coming back from the cloud.
class SegmentEncryptor {
  SegmentEncryptor({required KeyManager keyManager, SegmentCipher? cipher})
      : _keyManager = keyManager,
        _cipher = cipher ?? SegmentCipher();

  final KeyManager _keyManager;
  final SegmentCipher _cipher;

  /// Encrypts audio bytes for upload. The returned container is what is hashed,
  /// sized, and PUT to the cloud — the plaintext never leaves the device.
  Future<Uint8List> seal(Uint8List plaintext) {
    return _cipher.seal(plaintext: plaintext, wrapDek: _keyManager.wrapDek);
  }

  /// Decrypts a container fetched from the cloud. Bytes that are not a
  /// recognised container (legacy, pre-encryption objects) are returned as-is
  /// so older backups remain playable.
  Future<Uint8List> open(Uint8List bytes) {
    if (!SegmentCipher.looksEncrypted(bytes)) {
      return Future<Uint8List>.value(bytes);
    }
    return _cipher.open(container: bytes, unwrapDek: _keyManager.unwrapDek);
  }

  /// Whether on-device encryption is active. Always true once constructed;
  /// exposed so call sites can branch without a null-check on the encryptor.
  bool get enabled => true;
}
