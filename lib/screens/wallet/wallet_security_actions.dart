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
      builder: (ctx) => AlertDialog(
        title: const Text('Private key'),
        content: SelectableText(pk, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pk));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
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
        'Removes the saved recovery phrase from secure storage. '
        'Your on-chain funds are unchanged. You must have your seed phrase or private key to recover.\n\n'
        'The app will return to onboarding after this.\n\n'
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
  await onWalletErased?.call();
}
