import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// MODULE 6 — Pro tier: End-to-End Encrypted Cloud Sync
///
/// Zero-trust design:
///   1. User passphrase (never stored) + random salt → PBKDF2-HMAC-SHA256
///      → 256-bit *sync* key (separate from the local DB key).
///   2. Every payload is AES-256 encrypted ON DEVICE before upload.
///   3. The backend (Firebase Functions) only ever sees ciphertext.
///
/// Free tier: never called — everything stays local.
/// ─────────────────────────────────────────────────────────────────────────

class E2eSyncService {
  static const _saltKey = 'afa_sync_salt';
  static const _rounds = 60000;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// PBKDF2-HMAC-SHA256 implemented on package:crypto (RFC 2898).
  static Uint8List _pbkdf2(
      String passphrase, List<int> salt, int rounds, int keyLen) {
    final pw = utf8.encode(passphrase);
    final blockCount = (keyLen / 32).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blockCount; block++) {
      var u = Hmac(sha256, pw).convert([...salt, ..._int32be(block)]);
      var t = Uint8List.fromList(u.bytes);
      final result = Uint8List.fromList(u.bytes);
      for (var r = 1; r < rounds; r++) {
        u = Hmac(sha256, pw).convert(t);
        t = Uint8List.fromList(u.bytes);
        for (var i = 0; i < t.length; i++) {
          result[i] ^= t[i];
        }
      }
      out.add(result);
    }
    return out.toBytes();
  }

  static List<int> _int32be(int n) =>
      [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];

  Future<List<int>> _deriveSyncKey(String passphrase) async {
    var saltB64 = await _secure.read(key: _saltKey);
    if (saltB64 == null) {
      final rng = Random.secure();
      final salt = List<int>.generate(16, (_) => rng.nextInt(256));
      saltB64 = base64Encode(salt);
      await _secure.write(key: _saltKey, value: saltB64);
    }
    return _pbkdf2(passphrase, base64Decode(saltB64), _rounds, 32);
  }

  /// Encrypt an export payload for cloud sync (returns an envelope string).
  Future<String> encryptPayload(String passphrase, String plainJson) async {
    final keyBytes = await _deriveSyncKey(passphrase);
    final key = Key(Uint8List.fromList(keyBytes));
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encrypt(plainJson, iv: iv);
    return jsonEncode({
      'v': 1,
      'alg': 'AES-256-CBC+PBKDF2-SHA256',
      'iv': iv.base64,
      'ct': encrypted.base64,
    });
  }

  /// Decrypt on another device (same passphrase, same ciphertext).
  Future<String> decryptPayload(String passphrase, String envelopeJson) async {
    final keyBytes = await _deriveSyncKey(passphrase);
    final key = Key(Uint8List.fromList(keyBytes));
    final env = jsonDecode(envelopeJson) as Map<String, dynamic>;
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt64(env['ct'], iv: IV.fromBase64(env['iv']));
  }

  /// Upload/download: wire to your Firebase Functions endpoints
  /// (sync.v1/push, sync.v1/pull). Server stores opaque blobs only.
}
