import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/chain_config.dart';
import '../../services/bridge.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';

const _morTokenMainnet = '0x7431aDa8a591C955a994a21710752EF9b882b8e3';

/// Wallet actions: export key, send ETH/MOR, erase local wallet.
class WalletToolsScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;

  const WalletToolsScreen({super.key, this.onWalletErased});

  @override
  State<WalletToolsScreen> createState() => _WalletToolsScreenState();
}

class _WalletToolsScreenState extends State<WalletToolsScreen> {
  final _toCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  bool _sendMor = false;
  bool _busy = false;

  @override
  void dispose() {
    _toCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportPrivateKey() async {
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
            child: Text('Show key', style: TextStyle(color: RedPillTheme.amber)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final res = GoBridge().exportPrivateKey();
      final pk = res['private_key'] as String? ?? '';
      if (!mounted) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _submitSend() async {
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
    final asset = _sendMor ? 'MOR' : 'ETH';
    final humanSent = formatWeiForSendPreview(wei, isMor: _sendMor);

    setState(() => _busy = true);
    try {
      final bridge = GoBridge();
      final res = _sendMor
          ? bridge.sendMOR(toAddress: to, amountWei: weiStr)
          : bridge.sendETH(toAddress: to, amountWei: weiStr);
      final hash = res['tx_hash'] as String? ?? '';
      if (!mounted) return;
      _amtCtrl.clear();
      final explorerUri = Uri.parse(blockscoutTransactionUrl(hash));
      await showDialog<void>(
        context: context,
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
                'Submitted with full 18-decimal precision on Base (same as MetaMask).',
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
                      ScaffoldMessenger.of(context).showSnackBar(
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
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _eraseWallet() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase wallet on this device?'),
        content: const Text(
          'Removes the saved recovery phrase from the Keychain. '
          'Your on-chain funds are unchanged. You must have your seed phrase or private key to recover.\n\n'
          'The app will return to onboarding after this.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Erase', style: TextStyle(color: RedPillTheme.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await WalletVault.instance.clearMnemonic();
    await widget.onWalletErased?.call();
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('HOT WALLET', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(
            'Export or send at your own risk. Double-check addresses on Base mainnet.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          Card(
            child: ListTile(
              leading: const Icon(Icons.key_outlined, color: RedPillTheme.amber),
              title: const Text('Export private key'),
              subtitle: const Text('Import into MetaMask, Rabby, etc.'),
              onTap: _busy ? null : _exportPrivateKey,
            ),
          ),
          const SizedBox(height: 16),

          Text('SEND', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('ETH'), icon: Icon(Icons.currency_exchange, size: 18)),
                      ButtonSegment(value: true, label: Text('MOR'), icon: Icon(Icons.paid_outlined, size: 18)),
                    ],
                    selected: {_sendMor},
                    onSelectionChanged: _busy
                        ? null
                        : (s) {
                            setState(() => _sendMor = s.first);
                          },
                  ),
                  if (_sendMor) ...[
                    const SizedBox(height: 8),
                    Text('MOR token: $_morTokenMainnet', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _toCtrl,
                    decoration: const InputDecoration(
                      labelText: 'To address (0x…)',
                      hintText: '0x…',
                    ),
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amtCtrl,
                    decoration: InputDecoration(
                      labelText: 'Amount (${_sendMor ? 'MOR' : 'ETH'})',
                      hintText: _sendMor ? 'e.g. 0.05' : 'e.g. 0.005',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  _SendAmountPreview(
                    rawAmount: _amtCtrl.text,
                    isMor: _sendMor,
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type the amount like MetaMask (dot or comma as decimal). '
                    'We convert to the exact 18-decimal on-chain value. '
                    'Keep spare ETH on Base for gas when sending MOR.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submitSend,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_busy ? 'Sending…' : 'Send'),
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),
          Text('DANGER ZONE', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1F0A0A),
            child: ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: RedPillTheme.red.withValues(alpha: 0.9)),
              title: Text('Erase wallet from this device', style: TextStyle(color: RedPillTheme.red.withValues(alpha: 0.95))),
              subtitle: const Text('Clears Keychain phrase; see testing doc for full nuke'),
              onTap: _busy ? null : _eraseWallet,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'View transactions: $defaultBlockscoutWebOrigin/tx/…',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Live preview so the typed decimal matches what will be sent on-chain.
class _SendAmountPreview extends StatelessWidget {
  final String rawAmount;
  final bool isMor;
  final ThemeData theme;

  const _SendAmountPreview({
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
    final sym = isMor ? 'MOR' : 'ETH';
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
