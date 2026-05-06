import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/network_tokens.dart';
import '../../services/bridge.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';

/// Export private key — single dialog with warning + masked key + reveal/copy.
Future<void> showExportPrivateKeyFlow(BuildContext context) async {
  try {
    final res = GoBridge().exportPrivateKey();
    final pk = res['private_key'] as String? ?? '';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MaskedKeyDialog(privateKey: pk),
    );
  } on GoBridgeException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Erase local wallet — requires private key confirmation before proceeding.
Future<void> showEraseWalletFlow(
  BuildContext context, {
  Future<void> Function()? onWalletErased,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _PrivateKeyConfirmDialog(
      title: 'Erase wallet on this device?',
      description:
          'Removes the private key from secure storage. '
          'Your on-chain funds are unchanged — you must have your '
          'private key to recover this wallet.\n\n'
          'Your encrypted conversations will remain on this device. '
          'If you re-import this wallet later, they\'ll be restored automatically.\n\n'
          'Network: ${NetworkTokens.networkMainnetLabel}.',
      confirmLabel: 'Erase Wallet',
    ),
  );
  if (confirmed != true || !context.mounted) return;

  await WalletVault.instance.clearStoredSecret();
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  await onWalletErased?.call();
}

/// Factory reset — requires typing a confirmation phrase (no private key needed).
Future<bool?> showFactoryResetFlow(
  BuildContext context, {
  Future<void> Function()? onFactoryReset,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _PhraseConfirmDialog(
      title: 'Full Factory Reset?',
      description:
          'This will permanently delete:\n\n'
          '• All wallet private keys\n'
          '• All conversation history\n'
          '• All API keys and settings\n'
          '• All log files\n\n'
          'On-chain funds are unaffected, but you must have your '
          'private key to recover any wallet.\n\n'
          'This action cannot be undone.',
      phrase: 'DELETE ALL',
      confirmLabel: 'Erase Everything',
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  await onFactoryReset?.call();
  return true;
}

// ---------------------------------------------------------------------------
// Private key confirmation dialog (shared by erase + factory reset)
// ---------------------------------------------------------------------------

class _PrivateKeyConfirmDialog extends StatefulWidget {
  final String title;
  final String description;
  final String confirmLabel;

  const _PrivateKeyConfirmDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
  });

  @override
  State<_PrivateKeyConfirmDialog> createState() => _PrivateKeyConfirmDialogState();
}

class _PrivateKeyConfirmDialogState extends State<_PrivateKeyConfirmDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _verifying = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validateFormat(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final hex = trimmed.startsWith('0x') ? trimmed.substring(2) : trimmed;
    if (hex.length != 64) return 'Private key must be 64 hex characters (with or without 0x prefix)';
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return 'Invalid hex characters';
    return null;
  }

  bool get _inputValid {
    final trimmed = _ctrl.text.trim();
    if (trimmed.isEmpty) return false;
    return _validateFormat(trimmed) == null;
  }

  Future<void> _confirm() async {
    final input = _ctrl.text.trim();
    final formatErr = _validateFormat(input);
    if (formatErr != null) {
      setState(() => _error = formatErr);
      return;
    }

    setState(() { _verifying = true; _error = null; });

    try {
      final ok = GoBridge().verifyRecoveryPrivateKey(input);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Private key does not match the loaded wallet';
          _verifying = false;
        });
      }
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _verifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Verification failed: $e';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            Text(
              'Enter your private key to confirm:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NeoTheme.amber.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
              decoration: InputDecoration(
                hintText: '0x...',
                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _inputValid && !_verifying ? _confirm : null,
          style: FilledButton.styleFrom(
            backgroundColor: NeoTheme.red,
            disabledBackgroundColor: NeoTheme.red.withValues(alpha: 0.2),
          ),
          child: _verifying
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  widget.confirmLabel,
                  style: TextStyle(
                    color: _inputValid ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Phrase confirmation dialog (factory reset)
// ---------------------------------------------------------------------------

class _PhraseConfirmDialog extends StatefulWidget {
  final String title;
  final String description;
  final String phrase;
  final String confirmLabel;

  const _PhraseConfirmDialog({
    required this.title,
    required this.description,
    required this.phrase,
    required this.confirmLabel,
  });

  @override
  State<_PhraseConfirmDialog> createState() => _PhraseConfirmDialogState();
}

class _PhraseConfirmDialogState extends State<_PhraseConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _matches =>
      _ctrl.text.trim().toUpperCase() == widget.phrase.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description,
                style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NeoTheme.amber.withValues(alpha: 0.9),
                ),
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(
                    text: widget.phrase,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const TextSpan(text: ' to confirm:'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 14, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: widget.phrase,
                hintStyle:
                    const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: NeoTheme.red,
            disabledBackgroundColor: NeoTheme.red.withValues(alpha: 0.2),
          ),
          child: Text(
            widget.confirmLabel,
            style: TextStyle(
              color: _matches ? Colors.white : const Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Masked key display dialog (for export)
// ---------------------------------------------------------------------------

class _MaskedKeyDialog extends StatefulWidget {
  final String privateKey;
  const _MaskedKeyDialog({required this.privateKey});

  @override
  State<_MaskedKeyDialog> createState() => _MaskedKeyDialogState();
}

class _MaskedKeyDialogState extends State<_MaskedKeyDialog> {
  bool _revealed = false;

  String get _displayKey {
    if (_revealed) return widget.privateKey;
    final pk = widget.privateKey;
    if (pk.length <= 8) return '•' * pk.length;
    return '${pk.substring(0, 4)}${'•' * (pk.length - 8)}${pk.substring(pk.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.key_rounded, size: 18, color: NeoTheme.amber.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          const Text('Private Key'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anyone with this key controls your wallet on every chain. '
            'Use it to import into MetaMask or another app — never share it or screenshot it in insecure places.',
            style: TextStyle(fontSize: 12, color: const Color(0xFF9CA3AF), height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: SelectableText(
              _displayKey,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: _revealed ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280),
                letterSpacing: _revealed ? 0 : 1,
                height: 1.6,
              ),
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
                    size: 15,
                  ),
                  label: Text(_revealed ? 'Hide' : 'Reveal', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.privateKey));
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(
                        content: Text('Key copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: NeoTheme.green,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
