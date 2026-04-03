import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_brand.dart';
import '../../services/bridge.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';
import '../../widgets/morpheus_logo.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _mnemonicController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isCreating = false;
  String? _createdMnemonic;
  String? _createdAddress;
  bool _importByPrivateKey = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    setState(() => _isCreating = true);
    try {
      final bridge = GoBridge();
      final result = bridge.createWallet();
      setState(() {
        _createdMnemonic = result['mnemonic'] as String?;
        _createdAddress = result['address'] as String?;
        _isCreating = false;
      });
    } on GoBridgeException catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
      }
    }
  }

  Future<void> _confirmBackupAndFinish() async {
    final m = _createdMnemonic;
    if (m != null) {
      try {
        await WalletVault.instance.saveMnemonic(m);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Wallet save error: $e'), duration: const Duration(seconds: 6)),
          );
        }
        return;
      }
      _activateDbEncryption(m);
    }
    if (!mounted) return;
    widget.onComplete();
  }

  void _activateDbEncryption(String secret) {
    try {
      final keyBytes = sha256.convert(utf8.encode(secret.trim())).bytes;
      final keyHex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      GoBridge().setEncryptionKey(keyHex);
    } catch (e) {
      debugPrint('[Onboarding] setEncryptionKey failed (non-fatal): $e');
    }
  }

  Future<void> _importWalletByMnemonic() async {
    final mnemonic = _mnemonicController.text.trim();
    if (mnemonic.split(' ').length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 12 or 24-word mnemonic')),
      );
      return;
    }
    try {
      final bridge = GoBridge();
      bridge.importWalletMnemonic(mnemonic);
      await WalletVault.instance.saveMnemonic(mnemonic);
      _activateDbEncryption(mnemonic);
      if (!mounted) return;
      widget.onComplete();
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.message}')),
        );
      }
    }
  }

  Future<void> _importWalletByPrivateKey() async {
    var hexKey = _privateKeyController.text.trim();
    if (hexKey.startsWith('0x') || hexKey.startsWith('0X')) {
      hexKey = hexKey.substring(2);
    }
    if (hexKey.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 64-character hex private key')),
      );
      return;
    }
    try {
      final bridge = GoBridge();
      bridge.importWalletPrivateKey(hexKey);
      await WalletVault.instance.savePrivateKey(hexKey);
      _activateDbEncryption(hexKey);
      if (!mounted) return;
      widget.onComplete();
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.message}')),
        );
      }
    }
  }

  Future<void> _importWallet() async {
    if (_importByPrivateKey) {
      await _importWalletByPrivateKey();
    } else {
      await _importWalletByMnemonic();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdMnemonic != null) {
      return _MnemonicBackupScreen(
        mnemonic: _createdMnemonic!,
        address: _createdAddress ?? '',
        onConfirm: _confirmBackupAndFinish,
      );
    }
    return _buildOnboardingForm(context);
  }

  Widget _buildOnboardingForm(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 48),

                  const NeoLogo(size: 192),
                  const SizedBox(height: 20),

                  Image.asset(
                    'assets/branding/nodeneo_text.png',
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppBrand.tagline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createWallet,
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create New Wallet'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF374151))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or import existing', style: theme.textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF374151))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Import method toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF374151)),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _importByPrivateKey = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_importByPrivateKey
                                    ? NeoTheme.green.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: !_importByPrivateKey
                                    ? Border.all(color: NeoTheme.green.withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Text(
                                'Recovery Phrase',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: !_importByPrivateKey
                                      ? NeoTheme.green
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _importByPrivateKey = true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _importByPrivateKey
                                    ? NeoTheme.green.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: _importByPrivateKey
                                    ? Border.all(color: NeoTheme.green.withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Text(
                                'Private Key',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _importByPrivateKey
                                      ? NeoTheme.green
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_importByPrivateKey)
                    TextField(
                      controller: _privateKeyController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Enter hex private key (with or without 0x prefix)...',
                      ),
                      style: const TextStyle(fontSize: 14, fontFamily: 'JetBrains Mono'),
                    )
                  else
                    TextField(
                      controller: _mnemonicController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Enter your 12 or 24-word recovery phrase...',
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _importWallet,
                      child: const Text('Import Wallet'),
                    ),
                  ),
                  const SizedBox(height: 48),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NeoTheme.greenDark.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NeoTheme.green.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: NeoTheme.amber.withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your private key never leaves this device. '
                            'Secured by platform biometrics.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: NeoTheme.green.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the generated mnemonic so the user can back it up.
class _MnemonicBackupScreen extends StatelessWidget {
  final String mnemonic;
  final String address;
  final Future<void> Function() onConfirm;

  const _MnemonicBackupScreen({
    required this.mnemonic,
    required this.address,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = mnemonic.split(' ');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 48),
                  const NeoLogo(size: 144),
                  const SizedBox(height: 12),
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 40,
                    color: NeoTheme.green.withValues(alpha: 0.9),
                  ),
                  const SizedBox(height: 12),
                  Text('Wallet Created', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    address,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'JetBrains Mono'),
                  ),
                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NeoTheme.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Write down these 12 words and store them safely. '
                            'This is the ONLY way to recover your wallet.',
                            style: TextStyle(color: NeoTheme.amber.withValues(alpha: 0.9), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: NeoTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF374151)),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(words.length, (i) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}. ${words[i]}',
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 13,
                              color: Color(0xFFF9FAFB),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mnemonic));
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Mnemonic copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.only(bottom: 80, left: 24, right: 24),
                            duration: Duration(seconds: 2),
                          ),
                        );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy to clipboard'),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async => onConfirm(),
                      child: const Text("I've Backed It Up — Continue"),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
