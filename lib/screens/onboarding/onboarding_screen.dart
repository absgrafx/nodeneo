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
  bool _isCreating = false;
  String? _createdMnemonic;
  String? _createdAddress;

  @override
  void dispose() {
    _mnemonicController.dispose();
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
      await WalletVault.instance.saveMnemonic(m);
    }
    if (!mounted) return;
    widget.onComplete();
  }

  Future<void> _importWallet() async {
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

                  const MorpheusLogo(size: 96, variant: MorpheusLogoVariant.green),
                  const SizedBox(height: 16),

                  Text(
                    AppBrand.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Private AI inference on the\nMorpheus network',
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
                      color: RedPillTheme.greenDark.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: RedPillTheme.amber.withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your private key never leaves this device. '
                            'Secured by platform biometrics.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: RedPillTheme.green.withValues(alpha: 0.7),
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
                  const MorpheusLogo(size: 64, variant: MorpheusLogoVariant.green),
                  const SizedBox(height: 12),
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 40,
                    color: RedPillTheme.green.withValues(alpha: 0.9),
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
                      color: RedPillTheme.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: RedPillTheme.amber.withValues(alpha: 0.3)),
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
                            style: TextStyle(color: RedPillTheme.amber.withValues(alpha: 0.9), fontSize: 13),
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
                      color: RedPillTheme.surface,
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mnemonic copied to clipboard')),
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
