import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_brand.dart';
import '../../constants/external_links.dart';
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
  final _privateKeyController = TextEditingController();
  bool _isCreating = false;
  bool _isImporting = false;
  String? _createdPrivateKey;
  String? _createdAddress;

  @override
  void dispose() {
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    setState(() => _isCreating = true);
    try {
      final bridge = GoBridge();
      bridge.createWallet();
      final exported = bridge.exportPrivateKey();
      final pk = exported['private_key'] as String? ?? '';
      final summary = bridge.getWalletSummary();
      setState(() {
        _createdPrivateKey = pk;
        _createdAddress = summary['address'] as String?;
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
    final pk = _createdPrivateKey;
    if (pk != null && pk.isNotEmpty) {
      try {
        await WalletVault.instance.savePrivateKey(pk);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save error: $e'), duration: const Duration(seconds: 6)),
          );
        }
        return;
      }
      _openScopedDbAndEncrypt(pk);
    }
    if (!mounted) return;
    widget.onComplete();
  }

  /// Opens the wallet-scoped DB and sets the encryption key.
  /// Must be called after the wallet is imported into the Go SDK.
  void _openScopedDbAndEncrypt(String secret) {
    final bridge = GoBridge();
    try {
      final summary = bridge.getWalletSummary();
      var addr = (summary['address'] as String? ?? '').toLowerCase();
      if (addr.startsWith('0x')) addr = addr.substring(2);
      final fp = addr.length >= 8 ? addr.substring(0, 8) : addr;
      if (fp.isNotEmpty) {
        bridge.openWalletDatabase(fp);
      }
    } catch (e) {
      debugPrint('[Onboarding] openWalletDatabase failed (non-fatal): $e');
    }
    try {
      final keyBytes = sha256.convert(utf8.encode(secret.trim())).bytes;
      final keyHex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      bridge.setEncryptionKey(keyHex);
    } catch (e) {
      debugPrint('[Onboarding] setEncryptionKey failed (non-fatal): $e');
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
    setState(() => _isImporting = true);
    try {
      final bridge = GoBridge();
      bridge.importWalletPrivateKey(hexKey);
      await WalletVault.instance.savePrivateKey(hexKey);
      _openScopedDbAndEncrypt(hexKey);
      if (!mounted) return;
      widget.onComplete();
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdPrivateKey != null) {
      return _KeyBackupScreen(
        privateKey: _createdPrivateKey!,
        address: _createdAddress ?? '',
        onConfirm: _confirmBackupAndFinish,
      );
    }
    return _buildOnboardingForm(context);
  }

  Widget _buildOnboardingForm(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _isCreating || _isImporting;
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
                      onPressed: busy ? null : _createWallet,
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
                    controller: _privateKeyController,
                    maxLines: 2,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    decoration: const InputDecoration(
                      hintText: 'Paste your hex private key (with or without 0x prefix)',
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'JetBrains Mono'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: busy ? null : _importWalletByPrivateKey,
                      child: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Import Wallet'),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // "New to crypto?" — single-tap escape hatch into the
                  // long-form onboarding walkthrough on nodeneo.ai. Sized
                  // small on purpose: the user with a wallet ready should
                  // see the import flow as the dominant CTA; the user
                  // without one needs an answer that doesn't fit on this
                  // screen, and bouncing them to the website is honest.
                  Center(
                    child: TextButton.icon(
                      onPressed: () => ExternalLinks.launch(
                        ExternalLinks.onramp,
                        context: context,
                      ),
                      icon: const Icon(Icons.school_outlined, size: 16),
                      label: const Text(
                        'New to crypto? See the walkthrough',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: NeoTheme.emerald,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

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
                  const SizedBox(height: 20),

                  // Privacy / Terms acknowledgement. Apple's first-impression
                  // review wants this surface visible before the user creates
                  // any account-like artefact (the wallet, in our case). The
                  // links open the live nodeneo.ai pages so reviewers can
                  // verify the URLs claimed in the App Store record actually
                  // resolve to substantive policy text.
                  _LegalAcknowledgement(theme: theme),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline "By continuing you agree to … Terms … and … Privacy" line shown
/// at the bottom of [OnboardingScreen]. Kept as its own widget so the
/// `RichText` + tap-target plumbing doesn't bloat the main build method.
class _LegalAcknowledgement extends StatelessWidget {
  final ThemeData theme;
  const _LegalAcknowledgement({required this.theme});

  @override
  Widget build(BuildContext context) {
    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.hintColor,
      fontSize: 11,
      height: 1.5,
    );
    final link = base?.copyWith(
      color: NeoTheme.emerald,
      decoration: TextDecoration.underline,
      decorationColor: NeoTheme.emerald.withValues(alpha: 0.4),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'By creating or importing a wallet you agree to our '),
            TextSpan(
              text: 'Terms',
              style: link,
              recognizer: TapAndHoldGestureRecognizerFactory.createForUrl(
                context,
                ExternalLinks.terms,
              ),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: link,
              recognizer: TapAndHoldGestureRecognizerFactory.createForUrl(
                context,
                ExternalLinks.privacy,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Tiny factory wrapper that keeps the `TapGestureRecognizer` lifecycle
/// out of the widget body. Each call returns a one-shot recognizer wired
/// to launch [url] via [ExternalLinks.launch]; Flutter's text-span runtime
/// disposes the recognizer when the parent widget rebuilds, so we don't
/// need to track it ourselves.
class TapAndHoldGestureRecognizerFactory {
  TapAndHoldGestureRecognizerFactory._();

  static TapGestureRecognizer createForUrl(BuildContext context, String url) {
    return TapGestureRecognizer()
      ..onTap = () => ExternalLinks.launch(url, context: context);
  }
}

// ── Backup screen: masked private key with reveal & copy ────────

class _KeyBackupScreen extends StatefulWidget {
  final String privateKey;
  final String address;
  final Future<void> Function() onConfirm;

  const _KeyBackupScreen({
    required this.privateKey,
    required this.address,
    required this.onConfirm,
  });

  @override
  State<_KeyBackupScreen> createState() => _KeyBackupScreenState();
}

class _KeyBackupScreenState extends State<_KeyBackupScreen> {
  bool _revealed = false;
  bool _confirming = false;

  String get _displayKey {
    if (_revealed) return widget.privateKey;
    final pk = widget.privateKey;
    if (pk.length <= 8) return '•' * pk.length;
    return '${pk.substring(0, 4)}${'•' * (pk.length - 8)}${pk.substring(pk.length - 4)}';
  }

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: widget.privateKey));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Private key copied — paste into your password manager'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 24, right: 24),
          duration: Duration(seconds: 3),
        ),
      );
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
                  const SizedBox(height: 24),
                  const NeoLogo(size: 80),
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
                    widget.address,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'JetBrains Mono'),
                  ),
                  const SizedBox(height: 28),

                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NeoTheme.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: NeoTheme.amber.withValues(alpha: 0.9)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This is your wallet key — treat it like a password. '
                            'Copy it to a password manager now. It cannot be changed or recovered.',
                            style: TextStyle(color: NeoTheme.amber.withValues(alpha: 0.9), fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Masked key display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NeoTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF374151)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key_rounded, size: 14, color: NeoTheme.emerald.withValues(alpha: 0.6)),
                            const SizedBox(width: 6),
                            Text(
                              'Private Key',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NeoTheme.emerald.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          _displayKey,
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 13,
                            color: _revealed ? const Color(0xFFF9FAFB) : const Color(0xFF6B7280),
                            letterSpacing: _revealed ? 0 : 1,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _revealed = !_revealed),
                                icon: Icon(
                                  _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 16,
                                ),
                                label: Text(_revealed ? 'Hide' : 'Reveal', style: const TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _copyKey,
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy Key', style: TextStyle(fontSize: 12)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: NeoTheme.green,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirming
                          ? null
                          : () async {
                              setState(() => _confirming = true);
                              await widget.onConfirm();
                              if (mounted) setState(() => _confirming = false);
                            },
                      child: _confirming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("I've Saved My Key — Continue"),
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
