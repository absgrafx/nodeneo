import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'config/chain_config.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/network_settings_screen.dart';
import 'services/bridge.dart';
import 'services/rpc_settings_store.dart';
import 'services/wallet_vault.dart';
import 'theme.dart';

class RedPillApp extends StatefulWidget {
  const RedPillApp({super.key});

  @override
  State<RedPillApp> createState() => _RedPillAppState();
}

class _RedPillAppState extends State<RedPillApp> {
  bool _hasWallet = false;
  bool _sdkReady = false;
  String? _sdkError;

  @override
  void initState() {
    super.initState();
    _initSDK();
  }

  Future<void> _initSDK() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dataDir = '${dir.path}${Platform.pathSeparator}redpill';
      await Directory(dataDir).create(recursive: true);

      final ethUrl = await RpcSettingsStore.instance.effectiveRpcUrl();

      final bridge = GoBridge();
      final result = bridge.init(
        dataDir: dataDir,
        ethNodeURL: ethUrl,
        chainID: defaultBaseChainId,
        diamondAddr: defaultDiamondAddr,
        morTokenAddr: defaultMorTokenAddr,
        blockscoutURL: defaultBlockscoutApiV2,
      );

      if (result['status'] == 'ok') {
        var restored = false;
        try {
          final saved = await WalletVault.instance.readMnemonic();
          if (saved != null && saved.trim().isNotEmpty) {
            bridge.importWalletMnemonic(saved.trim());
            restored = true;
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
        setState(() => _sdkError = result['error'] ?? 'Unknown init error');
      }
    } catch (e) {
      setState(() => _sdkError = e.toString());
    }
  }

  void _onWalletCreated() {
    setState(() => _hasWallet = true);
  }

  /// After RPC settings change: tear down Go, re-init with new URL, restore wallet from vault.
  Future<void> _restartSdkAfterRpcChange() async {
    GoBridge().shutdown();
    if (!mounted) return;
    setState(() {
      _sdkReady = false;
      _sdkError = null;
    });
    await _initSDK();
  }

  /// Clears Go SDK + SQLite after [WalletVault] was cleared; returns to onboarding path.
  Future<void> _handleWalletErased() async {
    GoBridge().shutdown();
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
      title: 'RedPill',
      debugShowCheckedModeBanner: false,
      theme: RedPillTheme.dark,
      home: _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    if (_sdkError != null) {
      return _ErrorScreen(
        error: _sdkError!,
        onRetryDefaultRpc: _clearRpcOverrideAndRetry,
        onOpenNetworkSettings: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const NetworkSettingsScreen()),
          );
          if (!mounted) return;
          if (changed == true) {
            setState(() => _sdkError = null);
            await _restartSdkAfterRpcChange();
          }
        },
      );
    }
    if (!_sdkReady) {
      return const _LoadingScreen();
    }
    if (!_hasWallet) {
      return OnboardingScreen(onComplete: _onWalletCreated);
    }
    return HomeScreen(
      onWalletErased: _handleWalletErased,
      onOpenNetworkSettings: () async {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const NetworkSettingsScreen()),
        );
        if (!mounted) return;
        if (changed == true) await _restartSdkAfterRpcChange();
      },
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
            CircularProgressIndicator(color: RedPillTheme.green),
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
  final Future<void> Function()? onRetryDefaultRpc;
  final Future<void> Function()? onOpenNetworkSettings;

  const _ErrorScreen({
    required this.error,
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
                const Text('SDK Init Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                const SizedBox(height: 20),
                if (onOpenNetworkSettings != null)
                  FilledButton(
                    onPressed: () => onOpenNetworkSettings!(),
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                    child: const Text('Edit custom RPC'),
                  ),
                if (onOpenNetworkSettings != null) const SizedBox(height: 10),
                if (onRetryDefaultRpc != null)
                  OutlinedButton(
                    onPressed: () => onRetryDefaultRpc!(),
                    child: const Text('Reset to built-in public RPCs'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
