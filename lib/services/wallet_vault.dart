import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'keychain_sync_store.dart';

/// Persists the BIP-39 mnemonic in the OS credential store (macOS Keychain,
/// iOS Keychain, Android EncryptedSharedPreferences).
///
/// On first read, any legacy file-based mnemonic is automatically migrated
/// into the secure store and the old file is deleted.
class WalletVault {
  WalletVault._();
  static final WalletVault instance = WalletVault._();

  static const _keychainKey = 'nodeneo_mnemonic';
  static const _keychainKeyPK = 'nodeneo_private_key';

  static const _baseSecure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'Node Neo Wallet',
    ),
    mOptions: MacOsOptions(accountName: 'Node Neo Wallet'),
  );

  static Future<FlutterSecureStorage> _secure() async {
    final sync = await KeychainSyncStore.instance.isEnabled();
    if (!sync) return _baseSecure;
    return FlutterSecureStorage(
      aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        accountName: 'Node Neo Wallet',
      ),
      mOptions: MacOsOptions(
        accountName: 'Node Neo Wallet',
        synchronizable: sync,
      ),
    );
  }

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
      final s = await _secure();
      final existing = await s.read(key: _keychainKey);
      if (existing != null && existing.trim().isNotEmpty) return;

      final f = await _legacyFile();
      if (!f.existsSync()) return;
      final v = (await f.readAsString()).trim();
      if (v.isEmpty) return;

      await s.write(key: _keychainKey, value: v);
      await f.delete();
      debugPrint('[WalletVault] Migrated mnemonic from file to Keychain');
    } catch (e) {
      debugPrint('[WalletVault] Migration check failed (non-fatal): $e');
    }
  }

  Future<void> saveMnemonic(String mnemonic) async {
    final m = mnemonic.trim();
    if (m.isEmpty) return;
    final s = await _secure();
    await s.write(key: _keychainKey, value: m);
    debugPrint('[WalletVault] Mnemonic saved to Keychain');

    try {
      final f = await _legacyFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Store a hex private key when importing without a mnemonic.
  Future<void> savePrivateKey(String hexKey) async {
    final k = hexKey.trim();
    if (k.isEmpty) return;
    final s = await _secure();
    await s.write(key: _keychainKeyPK, value: k);
    debugPrint('[WalletVault] Private key saved to Keychain');
  }

  Future<String?> readMnemonic() async {
    await _migrateIfNeeded();
    try {
      final s = await _secure();
      final v = await s.read(key: _keychainKey);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (e) {
      debugPrint('[WalletVault] Keychain read failed: $e');
    }
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
    final s = await _secure();
    try { await s.delete(key: _keychainKey); } catch (_) {}
    try { await s.delete(key: _keychainKeyPK); } catch (_) {}
    try {
      final f = await _legacyFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<bool> hasSavedWallet() async {
    final mnemonic = await readMnemonic();
    if (mnemonic != null && mnemonic.trim().isNotEmpty) return true;
    try {
      final s = await _secure();
      final pk = await s.read(key: _keychainKeyPK);
      if (pk != null && pk.trim().isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  /// Returns the stored private key (for wallets imported by key, not mnemonic).
  Future<String?> readPrivateKey() async {
    try {
      final s = await _secure();
      final v = await s.read(key: _keychainKeyPK);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  /// Re-saves existing secrets with updated sync settings (call after toggling iCloud sync).
  Future<void> resyncKeychainItems() async {
    final s = await _secure();
    final mnemonic = await readMnemonic();
    if (mnemonic != null && mnemonic.trim().isNotEmpty) {
      await s.write(key: _keychainKey, value: mnemonic);
    }
    final pk = await readPrivateKey();
    if (pk != null && pk.trim().isNotEmpty) {
      await s.write(key: _keychainKeyPK, value: pk);
    }
    debugPrint('[WalletVault] Keychain items re-synced with updated iCloud preference');
  }
}
