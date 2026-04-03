import 'package:flutter/material.dart';

import '../../theme.dart';
import '../wallet/wallet_security_actions.dart';

/// Combined Wallet management screen: Export private key + Erase wallet.
class WalletScreen extends StatelessWidget {
  final Future<void> Function()? onWalletErased;

  const WalletScreen({super.key, this.onWalletErased});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'EXPORT',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.key_outlined,
            iconColor: NeoTheme.amber,
            title: 'Export Private Key',
            subtitle: 'For use with MetaMask, Rabby, or other wallets',
            onTap: () => showExportPrivateKeyFlow(context),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: NeoTheme.amber.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Never share your private key with anyone.',
                    style: TextStyle(
                      fontSize: 11,
                      color: NeoTheme.amber.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

          Text(
            'DANGER ZONE',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: NeoTheme.red.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NeoTheme.red.withValues(alpha: 0.25),
              ),
              color: NeoTheme.red.withValues(alpha: 0.05),
            ),
            child: _SettingsCard(
              icon: Icons.delete_forever_outlined,
              iconColor: NeoTheme.red.withValues(alpha: 0.9),
              title: 'Erase Wallet on This Device',
              titleColor: NeoTheme.red.withValues(alpha: 0.95),
              subtitle:
                  'Removes saved phrase from this device · on-chain funds unchanged',
              onTap: () => showEraseWalletFlow(
                context,
                onWalletErased: onWalletErased,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.hintColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
