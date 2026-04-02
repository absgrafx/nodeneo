import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/chain_config.dart';
import '../services/bridge.dart';
import '../theme.dart';

/// Confirm closing an on-chain session (same copy as the sessions list screen).
Future<bool> confirmCloseOnChainSession(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Close session on-chain?'),
      content: const Text(
        'This submits a close transaction and talks to the provider. '
        'It can take 30–90s. Stake is returned per contract rules.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// After a successful close, show tx hash + copy + Blockscout link.
Future<void> showCloseSessionTxBottomSheet(BuildContext context, String txHash) async {
  final tx = txHash.trim();
  final url = tx.isNotEmpty ? blockscoutTransactionUrl(tx) : '';

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: NeoTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B5563),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                tx.isNotEmpty ? 'Close transaction submitted' : 'Session closed',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (tx.isNotEmpty) ...[
                Text(
                  'Inspect on Base (Blockscout). Confirmation can take a short time.',
                  style: TextStyle(fontSize: 13, color: Theme.of(ctx).hintColor, height: 1.35),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  tx,
                  style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Color(0xFFE5E7EB)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: tx));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Transaction hash copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  label: const Text('Copy hash'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: url.isEmpty
                      ? null
                      : () async {
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Open in browser: $url')),
                            );
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  label: const Text('View on Blockscout'),
                ),
              ] else
                Text(
                  'No transaction hash was returned. The session may still be closing — refresh in a moment.',
                  style: TextStyle(fontSize: 13, color: Theme.of(ctx).hintColor, height: 1.35),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Runs close via Go bridge, shows sheet on success, returns true if closed without throwing.
Future<bool> runCloseOnChainSessionFlow(BuildContext context, String sessionId) async {
  final sid = sessionId.trim();
  if (sid.isEmpty) return false;
  final res = GoBridge().closeSession(sid);
  final tx = res['tx_hash'] as String? ?? '';
  if (context.mounted) {
    await showCloseSessionTxBottomSheet(context, tx);
  }
  return true;
}
