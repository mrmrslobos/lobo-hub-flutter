// lib/services/field_encryption_service.dart
// Per-family AES-256 field-level encryption for sensitive data at rest.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts / decrypts individual field values using AES-256-CBC with a
/// per-family key.  The key is derived from the family's join-code via
/// HMAC-SHA256 so every member who joined the family can derive the same key
/// without an explicit key-exchange step.
///
/// Encrypted values are stored as `enc:v1:<base64-iv>:<base64-ciphertext>` so
/// we can distinguish them from legacy plaintext during the migration window.
class FieldEncryption {
  FieldEncryption._();

  static const _prefix = 'enc:v1:';
  static const _storage = FlutterSecureStorage();

  // In-memory cache: familyId → Encrypter
  static final _cache = <String, Encrypter>{};
  static final _keyCache = <String, Key>{};

  // ── Key management ──────────────────────────────────────────────────────

  /// Derive (or load cached) AES-256 key for [familyId] using [joinCode].
  static Key _deriveKey(String familyId, String joinCode) {
    if (_keyCache.containsKey(familyId)) return _keyCache[familyId]!;

    // HMAC-SHA256(joinCode, familyId) → 32 bytes → AES-256 key
    final hmac = Hmac(sha256, utf8.encode(joinCode));
    final digest = hmac.convert(utf8.encode(familyId));
    final key = Key(Uint8List.fromList(digest.bytes));

    _keyCache[familyId] = key;
    _cache[familyId] = Encrypter(AES(key, mode: AESMode.cbc));
    return key;
  }

  /// Initialise encryption for a family.  Call once after authentication /
  /// family selection.  The [joinCode] is already available in the Family model.
  static Future<void> init(String familyId, String joinCode) async {
    _deriveKey(familyId, joinCode);
    // Persist the join-code in secure storage so we can re-derive on cold start
    // without needing the Family model loaded yet (belt-and-suspenders).
    await _storage.write(key: 'enc_jc_$familyId', value: joinCode);
  }

  /// Try to restore a previously-initialised key from secure storage.
  static Future<bool> restore(String familyId) async {
    final joinCode = await _storage.read(key: 'enc_jc_$familyId');
    if (joinCode == null || joinCode.isEmpty) return false;
    _deriveKey(familyId, joinCode);
    return true;
  }

  /// Whether encryption is ready for [familyId].
  static bool isReady(String familyId) => _cache.containsKey(familyId);

  /// Clear cached keys (e.g. on sign-out).
  static void clear() {
    _cache.clear();
    _keyCache.clear();
  }

  // ── Encrypt / Decrypt ───────────────────────────────────────────────────

  /// Encrypt a string value.  Returns the prefixed ciphertext string.
  /// Returns the original value unchanged if encryption isn't initialised.
  static String? encryptField(String? value, String familyId) {
    if (value == null || value.isEmpty) return value;
    final encrypter = _cache[familyId];
    if (encrypter == null) return value; // not initialised → passthrough
    try {
      final iv = IV.fromSecureRandom(16);
      final encrypted = encrypter.encrypt(value, iv: iv);
      return '$_prefix${iv.base64}:${encrypted.base64}';
    } catch (e) {
      debugPrint('[FieldEncryption] encrypt failed: $e');
      return value;
    }
  }

  /// Decrypt a value.  Handles both encrypted (prefixed) and legacy plaintext.
  static String? decryptField(String? value, String familyId) {
    if (value == null || value.isEmpty) return value;
    if (!value.startsWith(_prefix)) return value; // plaintext passthrough
    final encrypter = _cache[familyId];
    if (encrypter == null) return value; // can't decrypt → return raw
    try {
      final parts = value.substring(_prefix.length).split(':');
      if (parts.length != 2) return value;
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      debugPrint('[FieldEncryption] decrypt failed: $e');
      return value;
    }
  }

  /// Encrypt a numeric value by converting to string first.
  static String? encryptNum(num? value, String familyId) {
    if (value == null) return null;
    return encryptField(value.toString(), familyId);
  }

  /// Decrypt back to a double.  Falls back to parsing plaintext numbers.
  static double? decryptDouble(dynamic value, String familyId) {
    if (value == null) return null;
    if (value is num) return value.toDouble(); // legacy unencrypted number
    final str = decryptField(value.toString(), familyId);
    if (str == null) return null;
    return double.tryParse(str);
  }

  /// Decrypt back to an int.
  static int? decryptInt(dynamic value, String familyId) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final str = decryptField(value.toString(), familyId);
    if (str == null) return null;
    return int.tryParse(str);
  }

  /// Encrypt a JSON-serialisable object (list or map) by encoding to JSON
  /// string first, then encrypting.
  static String? encryptJson(dynamic value, String familyId) {
    if (value == null) return null;
    return encryptField(jsonEncode(value), familyId);
  }

  /// Decrypt a JSON blob.  Returns the parsed object (list or map).
  /// Falls back to returning [value] as-is if it's already decoded.
  static dynamic decryptJson(dynamic value, String familyId) {
    if (value == null) return null;
    if (value is! String) return value; // already decoded (legacy)
    if (!value.startsWith(_prefix)) {
      // Legacy — might be a JSON string or already-parsed
      try { return jsonDecode(value); } catch (_) { return value; }
    }
    final decrypted = decryptField(value, familyId);
    if (decrypted == null) return null;
    try { return jsonDecode(decrypted); } catch (_) { return decrypted; }
  }
}
