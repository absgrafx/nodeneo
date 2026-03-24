import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:url_launcher/url_launcher.dart';

import '../config/chain_config.dart';
import '../constants/network_tokens.dart';
import '../services/bridge.dart';
import '../theme.dart';
import '../utils/token_amount.dart';
import 'crypto_token_icons.dart';

const _morTokenMainnet = '0x7431aDa8a591C955a994a21710752EF9b882b8e3';

/// Modal bottom sheet: destination, amount, preview, confirm, then broadcast + success dialog.
Future<void> showSendTokenSheet(
  BuildContext context, {
  required bool sendMor,
  VoidCallback? onSent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _SendTokenSheetBody(
        parentContext: context,
        sendMor: sendMor,
        onSent: onSent,
      ),
    ),
  );
}

class _SendTokenSheetBody extends StatefulWidget {
  const _SendTokenSheetBody({
    required this.parentContext,
    required this.sendMor,
    this.onSent,
  });

  /// Context that stays valid after the sheet is closed (for the success dialog).
  final BuildContext parentContext;
  final bool sendMor;
  final VoidCallback? onSent;

  @override
  State<_SendTokenSheetBody> createState() => _SendTokenSheetBodyState();
}

class _SendTokenSheetBodyState extends State<_SendTokenSheetBody> {
  final _toCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _toCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final to = _toCtrl.text.trim();
    if (!to.startsWith('0x') || to.length != 42) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a full 0x address (42 characters)')),
      );
      return;
    }
    final wei = parseTokenAmountToWei(_amtCtrl.text);
    if (wei == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a positive amount using a decimal point (e.g. 0.05 MOR or 0.005 ETH)'),
        ),
      );
      return;
    }
    final weiStr = wei.toString();
    final asset = widget.sendMor ? NetworkTokens.morSymbol : NetworkTokens.ethSymbol;
    final humanSent = formatWeiForSendPreview(wei, isMor: widget.sendMor);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm send'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send $humanSent $asset to:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText(to, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final bridge = GoBridge();
      final res = widget.sendMor
          ? bridge.sendMOR(toAddress: to, amountWei: weiStr)
          : bridge.sendETH(toAddress: to, amountWei: weiStr);
      final hash = res['tx_hash'] as String? ?? '';
      if (!mounted) return;
      _amtCtrl.clear();
      if (mounted) Navigator.of(context).pop();
      widget.onSent?.call();
      final explorerUri = Uri.parse(blockscoutTransactionUrl(hash));
      final parent = widget.parentContext;
      if (!parent.mounted) return;
      await showDialog<void>(
        context: parent,
        builder: (ctx) => AlertDialog(
          title: const Text('Transaction sent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amount: $humanSent $asset',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Submitted with full 18-decimal precision (same as MetaMask).',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
              ),
              const SizedBox(height: 12),
              const Text('Tx hash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              SelectableText(hash, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: hash));
                      ScaffoldMessenger.of(parent).showSnackBar(
                        const SnackBar(content: Text('Tx hash copied')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy hash'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await canLaunchUrl(explorerUri)) {
                        await launchUrl(explorerUri, mode: LaunchMode.externalApplication);
                      } else if (parent.mounted) {
                        ScaffoldMessenger.of(parent).showSnackBar(
                          SnackBar(content: Text('Open: $explorerUri')),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Blockscout'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sym = widget.sendMor ? NetworkTokens.morSymbol : NetworkTokens.ethSymbol;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TokenWithBaseInlay(
                  token: widget.sendMor
                      ? const MorTokenIcon(size: 36)
                      : const EthTokenIcon(size: 36),
                  diameter: 36,
                  badgeDiameter: 14,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Send $sym',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste a destination address and amount. You’ll confirm before broadcasting.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
            ),
            if (widget.sendMor) ...[
              const SizedBox(height: 8),
              Text(
                '${NetworkTokens.morSymbol} token: $_morTokenMainnet',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(
                labelText: 'To address (0x…)',
                hintText: '0x…',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amtCtrl,
              decoration: InputDecoration(
                labelText: 'Amount ($sym)',
                hintText: widget.sendMor ? 'e.g. 0.05' : 'e.g. 0.005',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SendAmountPreview(
              rawAmount: _amtCtrl.text,
              isMor: widget.sendMor,
              theme: theme,
            ),
            const SizedBox(height: 8),
            Text(
              'Decimals like MetaMask. Keep spare ${NetworkTokens.ethSymbol} for gas when sending ${NetworkTokens.morSymbol}.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_busy ? 'Sending…' : 'Review & send'),
              style: FilledButton.styleFrom(
                backgroundColor: RedPillTheme.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview for typed decimal → on-chain wei.
class SendAmountPreview extends StatelessWidget {
  final String rawAmount;
  final bool isMor;
  final ThemeData theme;

  const SendAmountPreview({
    super.key,
    required this.rawAmount,
    required this.isMor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = rawAmount.trim();
    if (trimmed.isEmpty) {
      return Text(
        isMor ? 'Enter MOR using decimals (e.g. 0.05).' : 'Enter ETH using decimals (e.g. 0.005).',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      );
    }
    final wei = parseTokenAmountToWei(trimmed);
    if (wei == null) {
      return Text(
        'Could not parse amount. Use digits and one decimal separator.',
        style: theme.textTheme.bodySmall?.copyWith(color: RedPillTheme.red.withValues(alpha: 0.9)),
      );
    }
    final sym = isMor ? NetworkTokens.morSymbol : NetworkTokens.ethSymbol;
    final human = formatWeiForSendPreview(wei, isMor: isMor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.9)),
            children: [
              const TextSpan(text: 'You will send: '),
              TextSpan(
                text: '$human $sym',
                style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'JetBrains Mono'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'On-chain: ${wei.toString()} wei (18 decimals)',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.hintColor,
            fontFamily: 'JetBrains Mono',
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
