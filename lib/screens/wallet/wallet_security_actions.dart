import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/network_tokens.dart';
import '../../services/bridge.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';

/// Export private key — same flow as legacy Wallet screen; callable from ⋮ menu.
Future<void> showExportPrivateKeyFlow(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Export private key?'),
      content: const Text(
        'Anyone with this key controls your wallet on every chain. '
        'Use it to import into MetaMask or another app — never share it or screenshot it in insecure places.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Show key', style: TextStyle(color: NeoTheme.amber)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

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

/// Erase local wallet — callable from ⋮ menu. [onWalletErased] typically resets app root.
Future<void> showEraseWalletFlow(
  BuildContext context, {
  Future<void> Function()? onWalletErased,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Erase wallet on this device?'),
      content: Text(
        'Removes the private key from secure storage. '
        'Your on-chain funds are unchanged — you must have your '
        'private key to recover this wallet.\n\n'
        'Your encrypted conversations will remain on this device. '
        'If you re-import this wallet later, they\'ll be restored automatically.\n\n'
        'Network: ${NetworkTokens.networkMainnetLabel}.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Erase', style: TextStyle(color: NeoTheme.red)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  await WalletVault.instance.clearMnemonic();
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  await onWalletErased?.call();
}

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
