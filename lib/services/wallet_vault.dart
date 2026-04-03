import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the BIP-39 mnemonic in the OS credential store (macOS Keychain,
/// iOS Keychain, Android EncryptedSharedPreferences).
///
/// On first read, any legacy file-based mnemonic is automatically migrated
/// into the secure store and the old file is deleted.
class WalletVault {
  WalletVault._();
  static final WalletVault instance = WalletVault._();

  static const _keychainKey = 'nodeneo_mnemonic';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'Node Neo Wallet',
    ),
    mOptions: MacOsOptions(),
  );

  bool _migrated = false;

  // --- Legacy file path (pre-Keychain) ---

  static Future<File> _legacyFile() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    return File('${dir.path}${Platform.pathSeparator}.mnemonic_vault');
  }

  /// One-shot migration: copy file -> Keychain, then delete file.
  Future<void> _migrateIfNeeded() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final existing = await _secure.read(key: _keychainKey);
      if (existing != null && existing.trim().isNotEmpty) return;

      final f = await _legacyFile();
      if (!f.existsSync()) return;
      final v = (await f.readAsString()).trim();
      if (v.isEmpty) return;

      await _secure.write(key: _keychainKey, value: v);
      await f.delete();
      debugPrint('[WalletVault] Migrated mnemonic from file to Keychain');
    } catch (e) {
      debugPrint('[WalletVault] Migration check failed (non-fatal): $e');
    }
  }

  Future<void> saveMnemonic(String mnemonic) async {
    final m = mnemonic.trim();
    if (m.isEmpty) return;
    await _secure.write(key: _keychainKey, value: m);
    debugPrint('[WalletVault] Mnemonic saved to Keychain');

    // Clean up legacy file if it exists.
    try {
      final f = await _legacyFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<String?> readMnemonic() async {
    await _migrateIfNeeded();
    try {
      final v = await _secure.read(key: _keychainKey);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (e) {
      debugPrint('[WalletVault] Keychain read failed: $e');
    }
    // Last-resort fallback: try legacy file (e.g. Keychain not available).
    try {
      final f = await _legacyFile();
      if (f.existsSync()) {
        final v = (await f.readAsString()).trim();
        if (v.isNotEmpty) {
          debugPrint('[WalletVault] WARNING: using legacy file fallback — Keychain unavailable');
          return v;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> clearMnemonic() async {
    try {
      await _secure.delete(key: _keychainKey);
    } catch (_) {}
    try {
      final f = await _legacyFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<bool> hasSavedWallet() async {
    final v = await readMnemonic();
    return v != null && v.trim().isNotEmpty;
  }
}
