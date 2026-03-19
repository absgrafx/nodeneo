import 'package:flutter/material.dart';
import '../../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _mnemonicController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    setState(() => _isCreating = true);
    // TODO: call Go FFI — mobile.CreateWallet()
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _isCreating = false);
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
    // TODO: call Go FFI — mobile.ImportWalletMnemonic(mnemonic)
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
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

                  // Logo / shield
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: RedPillTheme.greenDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.3)),
                    ),
                    child: const Center(
                      child: Text('🛡️', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('RedPill', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Private AI inference on the\nMorpheusAIs network',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Create new wallet
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createWallet,
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create New Wallet'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF374151))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or import existing',
                            style: theme.textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF374151))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Import mnemonic
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

                  // Privacy note
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: RedPillTheme.greenDark.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: RedPillTheme.green.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔒', style: TextStyle(fontSize: 16)),
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
