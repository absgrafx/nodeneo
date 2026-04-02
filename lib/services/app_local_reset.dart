import 'dart:io';

import 'rpc_settings_store.dart';

/// Deletes on-disk data after [GoBridge.shutdown] (SQLite must be closed first).
///
/// Flutter secure storage is cleared separately via [WalletVault] / [AppLockService].
class AppLocalReset {
  AppLocalReset._();

  static Future<void> _tryDelete(String dataDir, String relativeName) async {
    final f = File('$dataDir${Platform.pathSeparator}$relativeName');
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Local chat / preferences SQLite only (keeps custom RPC and other files).
  static Future<void> wipeLocalDatabaseFiles(String dataDir) async {
    for (final name in ['nodeneo.db', 'nodeneo.db-wal', 'nodeneo.db-shm']) {
      await _tryDelete(dataDir, name);
    }
  }

  /// Factory reset: RPC override, SQLite, macOS fallback vault files.
  static Future<void> wipeFactoryLocalFiles(String dataDir) async {
    await RpcSettingsStore.instance.clearOverride();

    for (final name in [
      'nodeneo.db',
      'nodeneo.db-wal',
      'nodeneo.db-shm',
      'eth_rpc_override.txt',
      '.mnemonic_vault',
      '.app_lock_vault.json',
    ]) {
      await _tryDelete(dataDir, name);
    }
  }
}
