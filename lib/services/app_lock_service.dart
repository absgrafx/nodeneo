import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Optional app-level lock (password + optional biometrics) for a hot wallet UX.
/// Password is stored as SHA-256(salt:password); not the same secret as the mnemonic.
///
/// **macOS:** If Keychain returns errSecMissingEntitlement (-34018), e.g. unsigned
/// debug builds, we fall back to `Application Support/redpill/.app_lock_vault.json`
/// (same pattern as [WalletVault]).
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _kEnabled = 'app_lock_enabled';
  static const _kSalt = 'app_lock_salt';
  static const _kHash = 'app_lock_hash';
  static const _kBiometric = 'app_lock_biometric';

  static const _fileName = '.app_lock_vault.json';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(),
  );

  /// When false, [AppLockGate] shows the lock screen.
  final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  static bool _isKeychainEntitlementFailure(PlatformException e) {
    final blob = '${e.code} ${e.message} ${e.details}';
    return blob.contains('34018') || blob.contains("isn't present");
  }

  static Future<File> _vaultFile() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}redpill');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<Map<String, String>> _readFileMap() async {
    final f = await _vaultFile();
    if (!await f.exists()) return {};
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return {};
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeFileMap(Map<String, String> m) async {
    final f = await _vaultFile();
    if (m.isEmpty) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.writeAsString(jsonEncode(m), flush: true);
  }

  static Future<void> _mergeFileKey(String k, String v) async {
    final m = await _readFileMap();
    m[k] = v;
    await _writeFileMap(m);
  }

  static Future<void> _removeFileKey(String k) async {
    final m = await _readFileMap();
    m.remove(k);
    await _writeFileMap(m);
  }

  static Future<String?> _readFileKey(String k) async {
    final m = await _readFileMap();
    final v = m[k];
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> _clearVaultFile() async {
    final f = await _vaultFile();
    if (await f.exists()) await f.delete();
  }

  Future<String?> _readKey(String k) async {
    try {
      final v = await _storage.read(key: k);
      if (v != null && v.isNotEmpty) return v;
    } on PlatformException catch (e) {
      if (Platform.isMacOS && _isKeychainEntitlementFailure(e)) {
        return _readFileKey(k);
      }
      rethrow;
    }
    if (Platform.isMacOS) {
      final fv = await _readFileKey(k);
      if (fv != null && fv.isNotEmpty) return fv;
    }
    return null;
  }

  Future<void> _writeKey(String k, String v) async {
    try {
      await _storage.write(key: k, value: v);
      await _removeFileKey(k);
    } on PlatformException catch (e) {
      if (Platform.isMacOS && _isKeychainEntitlementFailure(e)) {
        await _mergeFileKey(k, v);
        return;
      }
      rethrow;
    }
  }

  Future<void> _deleteKey(String k) async {
    try {
      await _storage.delete(key: k);
    } catch (_) {}
    await _removeFileKey(k);
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

  /// Enable lock and persist password hash. Caller should set [unlocked] = true after.
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
    await _clearVaultFile();
    unlocked.value = true;
  }

  /// Removes stored lock credentials without changing [unlocked].
  /// Used when the app is resetting to onboarding (avoid flashing the home screen).
  Future<void> clearLockCredentialsOnly() async {
    await _deleteKey(_kEnabled);
    await _deleteKey(_kSalt);
    await _deleteKey(_kHash);
    await _deleteKey(_kBiometric);
    await _clearVaultFile();
  }

  void markUnlocked() {
    unlocked.value = true;
  }

  void markLocked() {
    unlocked.value = false;
  }

  /// If lock disabled, stay unlocked; if enabled, show lock screen.
  Future<void> applyColdStartPolicy() async {
    if (await isLockEnabled) {
      unlocked.value = false;
    } else {
      unlocked.value = true;
    }
  }
}
