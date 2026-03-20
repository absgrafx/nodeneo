import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the BIP-39 mnemonic in the platform secure store (macOS Keychain,
/// iOS Keychain, Android Keystore). The Go SDK keeps keys in memory only, so
/// on each cold start we [readMnemonic] and call `importWalletMnemonic`.
///
/// **macOS:** If Keychain returns errSecMissingEntitlement (-34018), e.g. unsigned
/// debug builds, we fall back to `Application Support/redpill/.mnemonic_vault`
/// (still inside the app sandbox). Keychain is preferred when entitlements + signing allow it.
class WalletVault {
  WalletVault._();
  static final WalletVault instance = WalletVault._();

  static const _mnemonicKey = 'redpill_bip39_mnemonic_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(),
  );

  static bool _isKeychainEntitlementFailure(PlatformException e) {
    final blob = '${e.code} ${e.message} ${e.details}';
    return blob.contains('34018') || blob.contains("isn't present");
  }

  static Future<File> _mnemonicFile() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}redpill');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}.mnemonic_vault');
  }

  static Future<void> _writeFallback(String m) async {
    final f = await _mnemonicFile();
    await f.writeAsString(m, flush: true);
  }

  static Future<String?> _readFallback() async {
    final f = await _mnemonicFile();
    if (!await f.exists()) return null;
    return (await f.readAsString()).trim();
  }

  static Future<void> _clearFallback() async {
    final f = await _mnemonicFile();
    if (await f.exists()) await f.delete();
  }

  Future<void> saveMnemonic(String mnemonic) async {
    final m = mnemonic.trim();
    if (m.isEmpty) return;
    try {
      await _storage.write(key: _mnemonicKey, value: m);
      await _clearFallback();
    } on PlatformException catch (e) {
      if (Platform.isMacOS && _isKeychainEntitlementFailure(e)) {
        await _writeFallback(m);
        return;
      }
      rethrow;
    }
  }

  Future<String?> readMnemonic() async {
    try {
      final v = await _storage.read(key: _mnemonicKey);
      if (v != null && v.isNotEmpty) return v;
    } on PlatformException catch (e) {
      if (Platform.isMacOS && _isKeychainEntitlementFailure(e)) {
        return _readFallback();
      }
      rethrow;
    }
    if (Platform.isMacOS) {
      final f = await _readFallback();
      if (f != null && f.isNotEmpty) return f;
    }
    return null;
  }

  Future<void> clearMnemonic() async {
    try {
      await _storage.delete(key: _mnemonicKey);
    } catch (_) {}
    await _clearFallback();
  }

  Future<bool> hasSavedWallet() async {
    final v = await readMnemonic();
    return v != null && v.trim().isNotEmpty;
  }
}
