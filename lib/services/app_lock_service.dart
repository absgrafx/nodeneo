import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Three-state shape of the on-device lock. Drives both the setup flow and
/// the unlock screen (e.g. whether to show the password fallback at all).
enum LockMode {
  /// No lock — app opens straight to the home screen.
  off,

  /// Face ID / Touch ID only. No password is stored, no fallback field is
  /// shown on the lock screen. Recovery is via wallet phrase / private key.
  biometricOnly,

  /// Password only — biometrics disabled or unavailable on the device.
  passwordOnly,

  /// Password is set and biometrics are enabled. Face ID is the primary path,
  /// password is a visible fallback after a biometric cancel / failure.
  passwordWithBiometric,
}

/// Optional app-level lock (Face ID / Touch ID and/or password) for a hot
/// wallet UX. When a password is set it is stored as SHA-256(salt:password);
/// it is **not** the same secret as the wallet mnemonic.
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
    mOptions: MacOsOptions(accountName: 'Node Neo App Lock'),
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

  /// True iff a password is currently stored. False for biometric-only mode
  /// or when the lock is off entirely.
  Future<bool> get hasPassword async {
    final salt = await _readKey(_kSalt);
    final hash = await _readKey(_kHash);
    return salt != null && hash != null;
  }

  /// Derive the current [LockMode] from the underlying secure-storage state.
  /// Cheap enough to call from a `FutureBuilder` per build; reads are cached
  /// by the platform Keychain.
  Future<LockMode> get mode async {
    if (!await isLockEnabled) return LockMode.off;
    final pw = await hasPassword;
    final bio = await biometricEnabled;
    if (!pw && bio) return LockMode.biometricOnly;
    if (pw && bio) return LockMode.passwordWithBiometric;
    if (pw) return LockMode.passwordOnly;
    // Edge case: enabled flag set but neither password nor biometric — treat
    // as off so we can never strand the user behind an empty lock screen.
    return LockMode.off;
  }

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

  /// Turn on the lock in **biometric-only** mode. Clears any pre-existing
  /// password material and enables the biometric flag. Caller is responsible
  /// for confirming the device actually supports Face ID / Touch ID first
  /// (e.g. `LocalAuthentication.canCheckBiometrics`).
  Future<void> enableBiometricLockOnly() async {
    await _deleteKey(_kSalt);
    await _deleteKey(_kHash);
    await _writeKey(_kBiometric, '1');
    await _writeKey(_kEnabled, '1');
  }

  /// Add a password as a fallback to an existing biometric-only lock,
  /// promoting it to [LockMode.passwordWithBiometric]. Idempotent for the
  /// password case — if a password is already set this just rotates it.
  Future<void> addPasswordFallback(String password) async {
    await enableLock(password);
  }

  /// Drop the password while keeping biometrics on, demoting from
  /// [LockMode.passwordWithBiometric] to [LockMode.biometricOnly]. Refuses
  /// to leave the user locked out: if biometrics are not enabled this is a
  /// no-op (caller should disable the lock entirely instead).
  Future<bool> removePasswordKeepBiometric() async {
    if (!await biometricEnabled) return false;
    await _deleteKey(_kSalt);
    await _deleteKey(_kHash);
    return true;
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
