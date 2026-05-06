import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'bridge.dart';
import 'keychain_sync_store.dart';

/// Persists the wallet's hex private key in the OS credential store
/// (macOS Keychain, iOS Keychain, Android EncryptedSharedPreferences).
///
/// As of v1.x the app is private-key-only — BIP-39 mnemonic / seed phrase
/// support has been removed from the user-facing surface. We still know how
/// to migrate any pre-existing mnemonic that an older build wrote to the
/// Keychain: see [migrateLegacyMnemonicToPrivateKey], which derives the PK
/// once via the Go SDK, swaps it into the vault, and wipes the mnemonic.
class WalletVault {
  WalletVault._();
  static final WalletVault instance = WalletVault._();

  /// Legacy keychain entry. Read-only — kept solely so we can migrate
  /// existing installs to the private-key-only model below. Never written
  /// by current code.
  static const _keychainKeyMnemonic = 'nodeneo_mnemonic';
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

  // ---------------------------------------------------------------------------
  // Legacy file path (pre-Keychain) — only relevant for the mnemonic migration
  // ---------------------------------------------------------------------------

  static Future<File> _legacyMnemonicFile() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    return File('${dir.path}${Platform.pathSeparator}.mnemonic_vault');
  }

  /// Returns any pre-existing mnemonic from the legacy file or the Keychain.
  /// Used solely to feed [migrateLegacyMnemonicToPrivateKey].
  Future<String?> _readLegacyMnemonic() async {
    try {
      final s = await _secure();
      final v = await s.read(key: _keychainKeyMnemonic);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (e) {
      debugPrint('[WalletVault] Legacy mnemonic Keychain read failed: $e');
    }
    try {
      final f = await _legacyMnemonicFile();
      if (f.existsSync()) {
        final v = (await f.readAsString()).trim();
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Public API — private key only
  // ---------------------------------------------------------------------------

  /// Store a hex private key (with or without 0x prefix; trimmed before write).
  Future<void> savePrivateKey(String hexKey) async {
    final k = hexKey.trim();
    if (k.isEmpty) return;
    final s = await _secure();
    await s.write(key: _keychainKeyPK, value: k);
    debugPrint('[WalletVault] Private key saved to Keychain');
  }

  /// Returns the stored private key, or `null` if none is saved.
  Future<String?> readPrivateKey() async {
    try {
      final s = await _secure();
      final v = await s.read(key: _keychainKeyPK);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  /// `true` when the device has either a stored private key or a legacy
  /// mnemonic awaiting migration.
  Future<bool> hasSavedWallet() async {
    final pk = await readPrivateKey();
    if (pk != null && pk.isNotEmpty) return true;
    final legacy = await _readLegacyMnemonic();
    return legacy != null && legacy.isNotEmpty;
  }

  /// Wipes every wallet secret this app may have written: current PK, legacy
  /// mnemonic Keychain entry, and the pre-Keychain mnemonic file. Safe to
  /// call when no secret is present.
  Future<void> clearStoredSecret() async {
    final s = await _secure();
    try { await s.delete(key: _keychainKeyPK); } catch (_) {}
    try { await s.delete(key: _keychainKeyMnemonic); } catch (_) {}
    try {
      final f = await _legacyMnemonicFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Re-saves the stored private key with the current iCloud-sync setting.
  /// Call after toggling [KeychainSyncStore]. Also opportunistically clears
  /// any leftover legacy mnemonic entry under the new sync setting.
  Future<void> resyncKeychainItems() async {
    final s = await _secure();
    final pk = await readPrivateKey();
    if (pk != null && pk.isNotEmpty) {
      await s.write(key: _keychainKeyPK, value: pk);
    }
    try { await s.delete(key: _keychainKeyMnemonic); } catch (_) {}
    debugPrint('[WalletVault] Keychain items re-synced with updated iCloud preference');
  }

  // ---------------------------------------------------------------------------
  // One-shot legacy migration: mnemonic ➜ private key
  // ---------------------------------------------------------------------------

  /// If a pre-existing mnemonic is present and no private key is saved yet,
  /// loads the wallet via the Go SDK, exports the derived account-zero
  /// private key, persists it, and removes the mnemonic from secure storage
  /// (and the legacy file if any).
  ///
  /// Returns the imported wallet's address on a successful migration, or
  /// `null` when there was nothing to migrate.
  ///
  /// Caller is responsible for ensuring the [GoBridge] has been initialized
  /// (it must be — we need to import the wallet to derive the PK).
  Future<String?> migrateLegacyMnemonicToPrivateKey(GoBridge bridge) async {
    final pk = await readPrivateKey();
    if (pk != null && pk.isNotEmpty) {
      // Already on the new model. Defensively clear any straggler mnemonic
      // entry so nuke-and-pave flows don't have to remember to.
      try {
        final s = await _secure();
        await s.delete(key: _keychainKeyMnemonic);
      } catch (_) {}
      try {
        final f = await _legacyMnemonicFile();
        if (f.existsSync()) await f.delete();
      } catch (_) {}
      return null;
    }

    final mnemonic = await _readLegacyMnemonic();
    if (mnemonic == null || mnemonic.isEmpty) return null;

    debugPrint('[WalletVault] Migrating legacy mnemonic to private key…');
    String? address;
    try {
      final imported = bridge.importWalletMnemonic(mnemonic);
      address = imported['address'] as String?;
      final exported = bridge.exportPrivateKey();
      final derived = (exported['private_key'] as String? ?? '').trim();
      if (derived.isEmpty) {
        debugPrint('[WalletVault] Migration: Go bridge returned empty private key — aborting');
        return null;
      }
      await savePrivateKey(derived);
    } on GoBridgeException catch (e) {
      debugPrint('[WalletVault] Migration failed (Go bridge): ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[WalletVault] Migration failed: $e');
      return null;
    }

    // Mnemonic is no longer needed — wipe both copies. We do this last so a
    // crash mid-migration leaves the original mnemonic intact.
    try {
      final s = await _secure();
      await s.delete(key: _keychainKeyMnemonic);
    } catch (_) {}
    try {
      final f = await _legacyMnemonicFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}

    debugPrint('[WalletVault] Migration complete (legacy mnemonic removed)');
    return address;
  }
}
