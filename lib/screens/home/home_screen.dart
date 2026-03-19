import 'package:flutter/material.dart';
import '../../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: RedPillTheme.greenDark,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.3)),
              ),
              child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 14))),
            ),
            const SizedBox(width: 10),
            const Text('RedPill', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wallet card
              _WalletCard(),
              const SizedBox(height: 24),

              // Section header
              Text('MODELS', style: theme.textTheme.labelSmall),
              const SizedBox(height: 12),

              // Model list placeholder
              Expanded(
                child: ListView(
                  children: [
                    _ModelTile(
                      name: 'LLaMA 3.1 70B',
                      provider: '0xabc...def',
                      isTEE: true,
                    ),
                    _ModelTile(
                      name: 'Mistral Large',
                      provider: '0x123...456',
                      isTEE: true,
                    ),
                    _ModelTile(
                      name: 'GPT-4o (via proxy)',
                      provider: '0x789...012',
                      isTEE: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: open new chat
        },
        backgroundColor: RedPillTheme.green,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('WALLET', style: theme.textTheme.labelSmall),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: RedPillTheme.greenDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'CONNECTED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: RedPillTheme.green,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '0x742d...35Fa',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrains Mono',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _BalanceChip(label: 'MOR', value: '—', color: RedPillTheme.green),
                _BalanceChip(label: 'ETH', value: '—', color: RedPillTheme.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BalanceChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final String name;
  final String provider;
  final bool isTEE;

  const _ModelTile({required this.name, required this.provider, required this.isTEE});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isTEE ? RedPillTheme.greenDark : RedPillTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isTEE
                  ? RedPillTheme.green.withValues(alpha: 0.3)
                  : const Color(0xFF374151),
            ),
          ),
          child: Center(
            child: Text(
              isTEE ? '🛡️' : '🤖',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        title: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
        subtitle: Text(provider, style: theme.textTheme.bodySmall),
        trailing: isTEE
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: RedPillTheme.greenDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'TEE',
                  style: TextStyle(
                    color: RedPillTheme.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
        onTap: () {
          // TODO: open chat with this model via QuickSession
        },
      ),
    );
  }
}
