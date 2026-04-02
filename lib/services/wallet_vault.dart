import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the BIP-39 mnemonic to the app-support directory.
///
/// TODO: migrate to Keychain (flutter_secure_storage) once signed builds
/// are validated end-to-end via CI. For now, file-based storage keeps
/// local development unblocked.
class WalletVault {
  WalletVault._();
  static final WalletVault instance = WalletVault._();

  static Future<File> _mnemonicFile() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}.mnemonic_vault');
  }

  Future<void> saveMnemonic(String mnemonic) async {
    final m = mnemonic.trim();
    if (m.isEmpty) return;
    final f = await _mnemonicFile();
    await f.writeAsString(m);
    debugPrint('[WalletVault] Mnemonic saved to ${f.path}');
  }

  Future<String?> readMnemonic() async {
    try {
      final f = await _mnemonicFile();
      if (!f.existsSync()) return null;
      final v = (await f.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (e) {
      debugPrint('[WalletVault] readMnemonic failed: $e');
      return null;
    }
  }

  Future<void> clearMnemonic() async {
    try {
      final f = await _mnemonicFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<bool> hasSavedWallet() async {
    final v = await readMnemonic();
    return v != null && v.trim().isNotEmpty;
  }
}
