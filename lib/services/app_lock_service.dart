import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Optional app-level lock (password + optional biometrics) for a hot wallet UX.
/// Password is stored as SHA-256(salt:password); not the same secret as the mnemonic.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _kEnabled = 'app_lock_enabled';
  static const _kSalt = 'app_lock_salt';
  static const _kHash = 'app_lock_hash';
  static const _kBiometric = 'app_lock_biometric';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'Node Neo App Lock',
    ),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  /// When false, [AppLockGate] shows the lock screen.
  final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  Future<String?> _readKey(String k) async {
    try {
      final v = await _storage.read(key: k);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('[AppLockService] Keychain read failed for $k: $e');
    }
    return null;
  }

  Future<void> _writeKey(String k, String v) async {
    await _storage.write(key: k, value: v);
  }

  Future<void> _deleteKey(String k) async {
    try {
      await _storage.delete(key: k);
    } catch (_) {}
  }

  Future<bool> get isLockEnabled async => (await _readKey(_kEnabled)) == '1';

  Future<bool> get biometricEnabled async => (await _readKey(_kBiometric)) == '1';

  Future<void> setBiometricEnabled(bool v) async {
    await _writeKey(_kBiometric, v ? '1' : '0');
  }

  String _hash(String salt, String password) {
    final bytes = utf8.encode('$salt:${password.trim()}');
    return sha256.convert(bytes).toString();
  }

  Future<void> enableLock(String password) async {
    final rnd = Random.secure();
    final salt = List.generate(20, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final hash = _hash(salt, password);
    await _writeKey(_kSalt, salt);
    await _writeKey(_kHash, hash);
    await _writeKey(_kEnabled, '1');
  }

  Future<bool> verifyPassword(String password) async {
    final salt = await _readKey(_kSalt);
    final hash = await _readKey(_kHash);
    if (salt == null || hash == null) return false;
    return _hash(salt, password) == hash;
  }

  Future<void> updatePassword(String newPassword) async {
    final salt = await _readKey(_kSalt);
    if (salt == null) {
      await enableLock(newPassword);
      return;
    }
    final hash = _hash(salt, newPassword);
    await _writeKey(_kHash, hash);
  }

  Future<void> disableLock() async {
    await _deleteKey(_kEnabled);
    await _deleteKey(_kSalt);
    await _deleteKey(_kHash);
    await _deleteKey(_kBiometric);
    unlocked.value = true;
  }

  Future<void> clearLockCredentialsOnly() async {
    await _deleteKey(_kEnabled);
    await _deleteKey(_kSalt);
    await _deleteKey(_kHash);
    await _deleteKey(_kBiometric);
  }

  void markUnlocked() {
    unlocked.value = true;
  }

  void markLocked() {
    unlocked.value = false;
  }

  Future<void> applyColdStartPolicy() async {
    if (await isLockEnabled) {
      unlocked.value = false;
    } else {
      unlocked.value = true;
    }
  }
}
