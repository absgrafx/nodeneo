import 'dart:io';

import 'app_lock_service.dart';
import 'app_logger.dart';
import 'wallet_vault.dart';

/// Reconciles platform Keychain state with the app's container state on every
/// launch. The motivating problem is iOS-specific: when a user deletes the app
/// from the Home screen, iOS wipes the app container (Documents, Library, the
/// SQLite store) but **leaves Keychain items intact** for the bundle ID. On
/// reinstall the user expects "their data is gone" and is confused when the
/// previous wallet quietly reappears.
///
/// We detect a fresh install by writing a sentinel file inside the app's data
/// directory. On startup, if the sentinel is missing the container has been
/// wiped (or this is genuinely the first launch ever). In that case we treat
/// any pre-existing Keychain material as orphaned and clear it before the rest
/// of `_initSDK` has a chance to read it back. The sentinel is then written so
/// every subsequent launch is a no-op.
///
/// The same logic applies on macOS — Keychain entries also outlive the .app
/// being moved to Trash. On Android `flutter_secure_storage` lives in the app
/// container (EncryptedSharedPreferences) and is already cleared by an
/// uninstall, so the wipe step is a harmless no-op there.
class FirstLaunchGuard {
  FirstLaunchGuard._();

  static const _sentinelName = '.install_sentinel';

  /// Call exactly once per cold start, immediately after [dataDir] exists and
  /// **before** any code reads from [WalletVault] or [AppLockService].
  ///
  /// Returns `true` when this launch was treated as a fresh install (Keychain
  /// was wiped, sentinel was created); useful for telemetry / banners.
  static Future<bool> reconcileFreshInstall(String dataDir) async {
    final sentinel = File('$dataDir${Platform.pathSeparator}$_sentinelName');

    if (await sentinel.exists()) {
      return false;
    }

    AppLogger.info(
      '[FirstLaunchGuard] Sentinel missing — treating as fresh install '
      '(container was wiped or first run ever). Clearing any orphaned Keychain entries.',
    );

    try {
      await WalletVault.instance.clearStoredSecret();
    } catch (e) {
      AppLogger.warn('[FirstLaunchGuard] WalletVault wipe failed (non-fatal): $e');
    }
    try {
      await AppLockService.instance.clearLockCredentialsOnly();
    } catch (e) {
      AppLogger.warn('[FirstLaunchGuard] AppLock wipe failed (non-fatal): $e');
    }

    try {
      await sentinel.create(recursive: true);
      // Best-effort timestamp body. The mere existence of the file is what we
      // check, but a human-readable marker helps when triaging support reports.
      await sentinel.writeAsString(
        'created=${DateTime.now().toUtc().toIso8601String()}\n',
      );
    } catch (e) {
      AppLogger.warn(
        '[FirstLaunchGuard] Sentinel write failed (non-fatal): $e — '
        'next launch will redundantly re-wipe but app will still function.',
      );
    }

    return true;
  }
}
