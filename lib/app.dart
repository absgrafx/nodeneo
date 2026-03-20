import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/bridge.dart';
import 'theme.dart';

// Base Sepolia testnet defaults — swap for mainnet in production
const _defaultEthNodeURL = 'https://sepolia.base.org';
const _defaultChainID = 84532;
const _defaultDiamondAddr = '0x8e19288d908b2d9F8D7C539c74C899808AC3dE45';
const _defaultMorTokenAddr = '0xc1664f994Fd3991f98aE944bC16B9aED673eF5fD';
const _defaultBlockscoutURL = 'https://base-sepolia.blockscout.com/api/v2';

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

      final bridge = GoBridge();
      final result = bridge.init(
        dataDir: dataDir,
        ethNodeURL: _defaultEthNodeURL,
        chainID: _defaultChainID,
        diamondAddr: _defaultDiamondAddr,
        morTokenAddr: _defaultMorTokenAddr,
        blockscoutURL: _defaultBlockscoutURL,
      );

      if (result['status'] == 'ok') {
        setState(() => _sdkReady = true);
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedPill',
      debugShowCheckedModeBanner: false,
      theme: RedPillTheme.dark,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_sdkError != null) {
      return _ErrorScreen(error: _sdkError!);
    }
    if (!_sdkReady) {
      return const _LoadingScreen();
    }
    if (!_hasWallet) {
      return OnboardingScreen(onComplete: _onWalletCreated);
    }
    return const HomeScreen();
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
  const _ErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              const Text('SDK Init Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(error, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
