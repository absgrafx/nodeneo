import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'constants/app_brand.dart';
import 'config/chain_config.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/network_settings_screen.dart';
import 'services/app_lock_service.dart';
import 'services/bridge.dart';
import 'services/rpc_settings_store.dart';
import 'services/app_local_reset.dart';
import 'services/app_logger.dart';
import 'services/wallet_vault.dart';
import 'app_route_observer.dart';
import 'theme.dart';
import 'widgets/app_lock_gate.dart';

/// Top-level so [compute] can serialize it across isolate boundaries
/// (instance-method closures capture `this` which includes unsendable widgets).
Map<String, dynamic> _initBridgeSync(Map<String, dynamic> p) {
  final bridge = GoBridge();
  return bridge.init(
    dataDir: p['dataDir'] as String,
    ethNodeURL: p['ethNodeURL'] as String,
    chainID: p['chainID'] as int,
    diamondAddr: p['diamondAddr'] as String,
    morTokenAddr: p['morTokenAddr'] as String,
    blockscoutURL: p['blockscoutURL'] as String,
  );
}

class NodeNeoApp extends StatefulWidget {
  const NodeNeoApp({super.key});

  @override
  State<NodeNeoApp> createState() => _NodeNeoAppState();
}

class _NodeNeoAppState extends State<NodeNeoApp> with WidgetsBindingObserver {
  bool _hasWallet = false;
  bool _sdkReady = false;
  String? _sdkError;
  /// False when failure is missing native lib (iOS): RPC buttons are misleading.
  bool _showRpcRecoveryOnError = true;

  /// True when the app was launched from a mounted DMG volume — the user needs
  /// to drag it to /Applications first.
  bool _runningFromDmg = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_detectDmgLaunch()) {
      _runningFromDmg = true;
    } else {
      _initSDK();
    }
  }

  /// Detect if the app binary lives on a mounted disk image instead of /Applications.
  static bool _detectDmgLaunch() {
    if (!Platform.isMacOS) return false;
    if (kDebugMode) return false; // dev builds run from repo on /Volumes — not a DMG
    final exe = Platform.resolvedExecutable;
    // Mounted DMG volumes appear under /Volumes/ and never under /Applications.
    if (exe.startsWith('/Volumes/') && !exe.contains('/Applications/')) {
      return true;
    }
    // macOS App Translocation (GateKeeper) moves unsigned apps to a random path
    // under /private/var/folders when run from a quarantined location.
    if (exe.contains('/AppTranslocation/')) return true;
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      Future<void>.microtask(() async {
        if (await AppLockService.instance.isLockEnabled) {
          AppLockService.instance.markLocked();
        }
      });
    }
  }

  Future<void> _initSDK() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dataDir = '${dir.path}${Platform.pathSeparator}nodeneo';
      await Directory(dataDir).create(recursive: true);

      final ethUrl = await RpcSettingsStore.instance.effectiveRpcUrl();

      AppLogger.info('_initSDK: dataDir=$dataDir  rpc=${hasBuildTimeRpc ? "(dedicated)" : ethUrl}');

      // Go's sdk.NewSDK() may block for seconds (network, DNS) — run the
      // synchronous FFI call on a background isolate so the UI stays alive.
      // Must use a top-level function; closures in instance methods capture
      // `this` which includes unsendable Flutter widget-tree objects.
      final initParams = <String, dynamic>{
        'dataDir': dataDir,
        'ethNodeURL': ethUrl,
        'chainID': defaultBaseChainId,
        'diamondAddr': defaultDiamondAddr,
        'morTokenAddr': defaultMorTokenAddr,
        'blockscoutURL': defaultBlockscoutApiV2,
      };

      // No Dart-side timeout — let Go's NewSDK() finish naturally.
      // The "Connecting to network..." spinner stays visible. If the RPC is
      // slow (public endpoints can take 60-120s), the SDK still succeeds.
      // If Go hits a real error, it returns it; we show the error screen then.
      final result = await compute(_initBridgeSync, initParams);

      AppLogger.info('init result: $result');

      final bridge = GoBridge();
      final st = result['status'] as String?;
      bridge.initialized = st == 'ok' || st == 'already_initialized';

      if (bridge.initialized) {
        var restored = false;
        try {
          String? walletSecret;
          String? walletAddress;
          final saved = await WalletVault.instance.readMnemonic();
          if (saved != null && saved.trim().isNotEmpty) {
            final result = bridge.importWalletMnemonic(saved.trim());
            walletAddress = result['address'] as String?;
            walletSecret = saved.trim();
            restored = true;
          } else {
            final pk = await WalletVault.instance.readPrivateKey();
            if (pk != null && pk.trim().isNotEmpty) {
              final result = bridge.importWalletPrivateKey(pk.trim());
              walletAddress = result['address'] as String?;
              walletSecret = pk.trim();
              restored = true;
            }
          }
          if (walletAddress != null && walletAddress.isNotEmpty) {
            final fp = _walletFingerprint(walletAddress);
            bridge.openWalletDatabase(fp);
          }
          if (walletSecret != null) {
            _activateDbEncryption(bridge, walletSecret);
          }
        } on GoBridgeException catch (_) {
          await WalletVault.instance.clearMnemonic();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _sdkReady = true;
          _sdkError = null;
          if (restored) _hasWallet = true;
        });
      } else {
        if (!mounted) return;
        setState(() => _sdkError = result['error'] ?? 'Unknown init error');
      }
    } catch (e) {
      AppLogger.error('_initSDK exception: $e');
      if (!mounted) return;
      setState(() => _sdkError = e.toString());
    }
  }

  /// First 8 hex chars of the address (lowercase, no 0x prefix).
  static String _walletFingerprint(String address) {
    var addr = address.toLowerCase().trim();
    if (addr.startsWith('0x')) addr = addr.substring(2);
    return addr.length >= 8 ? addr.substring(0, 8) : addr;
  }

  static void _activateDbEncryption(GoBridge bridge, String secret) {
    try {
      final keyBytes = sha256.convert(utf8.encode(secret.trim())).bytes;
      final keyHex =
          keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      bridge.setEncryptionKey(keyHex);
    } catch (e) {
      AppLogger.warn('setEncryptionKey failed (non-fatal): $e');
    }
  }

  void _onWalletCreated() {
    setState(() => _hasWallet = true);
  }

  /// After RPC settings change: tear down Go, re-init with new URL, restore wallet from vault.
  Future<void> _restartSdkAfterRpcChange() async {
    await _safeShutdown();
    if (!mounted) return;
    setState(() {
      _sdkReady = false;
      _sdkError = null;
    });
    await _initSDK();
  }

  /// Clears Go SDK + app lock after [WalletVault] was cleared; returns to onboarding.
  /// The encrypted DB is intentionally kept — if the user re-imports the same
  /// wallet later, conversations auto-reconnect via the fingerprinted DB name.
  Future<void> _handleWalletErased() async {
    await _safeShutdown();
    await AppLockService.instance.clearLockCredentialsOnly();
    if (!mounted) return;
    setState(() {
      _sdkReady = false;
      _hasWallet = false;
    });
    await _initSDK();
  }

  /// Shutdown with a timeout — avoids UI freeze if Go mutex is held by a slow Init.
  static Future<void> _safeShutdown() async {
    try {
      await compute((_) { GoBridge().shutdown(); return true; }, null).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.warn('Shutdown timed out (Go mutex likely held by slow Init)');
          return false;
        },
      );
    } catch (e) {
      AppLogger.warn('Shutdown error (non-fatal): $e');
    }
  }

  /// Factory reset: ALL wallets, keys, DBs, logs, settings — nuclear option.
  Future<void> _fullFactoryReset() async {
    await WalletVault.instance.clearMnemonic();
    await AppLockService.instance.clearLockCredentialsOnly();
    await _safeShutdown();
    final dir = await getApplicationSupportDirectory();
    final dataDir = '${dir.path}${Platform.pathSeparator}nodeneo';
    await AppLocalReset.wipeFactoryLocalFiles(dataDir);
    if (!mounted) return;
    setState(() {
      _sdkReady = false;
      _hasWallet = false;
    });
    await _initSDK();
  }

  Future<void> _clearRpcOverrideAndRetry() async {
    await RpcSettingsStore.instance.clearOverride();
    if (!mounted) return;
    setState(() => _sdkError = null);
    await _restartSdkAfterRpcChange();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.displayName,
      debugShowCheckedModeBanner: false,
      theme: NeoTheme.dark,
      navigatorObservers: <NavigatorObserver>[neoRouteObserver],
      // Builder gives a context that is *below* MaterialApp's Navigator.
      // Using State.context here would break Navigator.of in callbacks (e.g. Network / RPC).
      home: Builder(
        builder: (context) => _buildHome(context),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    if (_runningFromDmg) {
      return const _DmgWarningScreen();
    }
    if (_sdkError != null) {
      return _ErrorScreen(
        error: _sdkError!,
        showRpcRecoveryActions: _showRpcRecoveryOnError,
        onRetryDefaultRpc: _showRpcRecoveryOnError ? _clearRpcOverrideAndRetry : null,
        onOpenNetworkSettings: _showRpcRecoveryOnError
            ? () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const NetworkSettingsScreen()),
                );
                if (!mounted) return;
                if (changed == true) {
                  setState(() => _sdkError = null);
                  await _restartSdkAfterRpcChange();
                }
              }
            : null,
      );
    }
    if (!_sdkReady) {
      return const _LoadingScreen();
    }
    if (!_hasWallet) {
      return OnboardingScreen(onComplete: _onWalletCreated);
    }
    return AppLockGate(
      onFullFactoryReset: _fullFactoryReset,
      child: HomeScreen(
        onWalletErased: _handleWalletErased,
        onRpcChanged: _restartSdkAfterRpcChange,
        onFactoryReset: _fullFactoryReset,
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: NeoTheme.green),
            SizedBox(height: 24),
            Text('Connecting to network...', style: TextStyle(color: Color(0xFF9CA3AF))),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  /// When false (e.g. missing native lib on iOS), hide RPC-related actions.
  final bool showRpcRecoveryActions;
  final Future<void> Function()? onRetryDefaultRpc;
  final Future<void> Function()? onOpenNetworkSettings;

  const _ErrorScreen({
    required this.error,
    this.showRpcRecoveryActions = true,
    this.onRetryDefaultRpc,
    this.onOpenNetworkSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  showRpcRecoveryActions ? 'SDK Init Failed' : 'Not available on this build',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      error,
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (showRpcRecoveryActions) ...[
                  const SizedBox(height: 20),
                  if (onOpenNetworkSettings != null)
                    FilledButton(
                      onPressed: () => onOpenNetworkSettings!(),
                      style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                      child: const Text('Edit custom RPC'),
                    ),
                  if (onOpenNetworkSettings != null) const SizedBox(height: 10),
                  if (onRetryDefaultRpc != null)
                    OutlinedButton(
                      onPressed: () => onRetryDefaultRpc!(),
                      child: const Text('Reset to built-in public RPCs'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the app is launched directly from a mounted DMG volume.
class _DmgWarningScreen extends StatelessWidget {
  const _DmgWarningScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NeoTheme.green.withValues(alpha: 0.12),
                    border: Border.all(color: NeoTheme.green.withValues(alpha: 0.35), width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.drive_file_move_rounded, size: 36, color: NeoTheme.green),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Install ${AppBrand.displayName}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  'You\'re running ${AppBrand.displayName} directly from the disk image.\n\n'
                  'Drag ${AppBrand.displayName} into your Applications folder first, '
                  'then open it from there. This ensures Keychain access, '
                  'automatic updates, and proper macOS security.',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: NeoTheme.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NeoTheme.green.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.apps_rounded, size: 28, color: NeoTheme.green.withValues(alpha: 0.85)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(Icons.arrow_forward_rounded, size: 22, color: NeoTheme.green.withValues(alpha: 0.6)),
                      ),
                      const Icon(Icons.folder_rounded, size: 28, color: Color(0xFF60A5FA)),
                      const SizedBox(width: 8),
                      const Text('/Applications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'After moving, eject the disk image and re-open the app.',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
