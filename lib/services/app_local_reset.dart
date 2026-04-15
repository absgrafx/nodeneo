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

  /// Wipe a specific wallet-scoped DB: nodeneo_{fingerprint}.db + WAL/SHM.
  static Future<void> wipeWalletDatabase(String dataDir, String fingerprint) async {
    final base = 'nodeneo_$fingerprint.db';
    for (final suffix in ['', '-wal', '-shm']) {
      await _tryDelete(dataDir, '$base$suffix');
    }
  }

  /// Wipe ALL wallet databases (nodeneo_*.db) + legacy nodeneo.db.
  static Future<void> wipeAllDatabaseFiles(String dataDir) async {
    // Legacy
    for (final name in ['nodeneo.db', 'nodeneo.db-wal', 'nodeneo.db-shm']) {
      await _tryDelete(dataDir, name);
    }
    // Scoped wallet DBs
    final dir = Directory(dataDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('nodeneo_') && (name.endsWith('.db') || name.endsWith('.db-wal') || name.endsWith('.db-shm'))) {
            try { await entity.delete(); } catch (_) {}
          }
        }
      }
    }
  }

  /// Wipe the logs directory.
  static Future<void> wipeLogs(String dataDir) async {
    final logsDir = Directory('$dataDir${Platform.pathSeparator}logs');
    if (await logsDir.exists()) {
      try {
        await logsDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Full factory reset: ALL wallet DBs, logs, RPC override, vault files.
  /// Removes the entire Node Neo data footprint except the app binary.
  static Future<void> wipeFactoryLocalFiles(String dataDir) async {
    await RpcSettingsStore.instance.clearOverride();
    await wipeAllDatabaseFiles(dataDir);
    await wipeLogs(dataDir);

    // Legacy files (migrated to SQLite preferences but may still exist
    // on devices that haven't triggered migration yet).
    for (final name in [
      'eth_rpc_override.txt',
      '.mnemonic_vault',
      '.app_lock_vault.json',
      'chat_streaming_preference.txt',
      'default_tuning.json',
      'default_session_duration_seconds.txt',
      'session_duration_seconds.txt',
      'keychain_icloud_sync.txt',
    ]) {
      await _tryDelete(dataDir, name);
    }
  }
}
