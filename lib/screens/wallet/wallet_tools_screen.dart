import 'package:flutter/material.dart';

import '../../config/chain_config.dart';
import '../../constants/network_tokens.dart';

/// Lightweight wallet info. **Send** is started from the home card (tap MOR or ETH).
/// Export / erase live under the ⋮ menu on Home.
class WalletToolsScreen extends StatelessWidget {
  const WalletToolsScreen({super.key});

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
          Text('YOUR WALLET', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(
            'Send ${NetworkTokens.morSymbol} or ${NetworkTokens.ethSymbol} from the home screen: '
            'tap a balance tile to open the send sheet (address, amount, confirm, then broadcast).',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('More actions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Export private key and erase wallet are in the ⋮ menu on the home app bar.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('BLOCK EXPLORER', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          SelectableText(
            '$defaultBlockscoutWebOrigin/tx/…',
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'JetBrains Mono', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
