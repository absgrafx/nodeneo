import 'package:flutter/material.dart';
import '../../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _maxPrivacy = false;

  // Mock data — will be replaced with Go FFI calls
  final List<_MockModel> _allModels = [
    _MockModel('LLaMA 3.1 70B', '0xabc...def', true, ['LLM', 'TEE']),
    _MockModel('Mistral Large', '0x123...456', true, ['LLM', 'TEE']),
    _MockModel('GPT-4o (via proxy)', '0x789...012', false, ['LLM']),
    _MockModel('Claude Sonnet', '0xdef...789', false, ['LLM']),
    _MockModel('Whisper Large v3', '0x456...abc', true, ['STT', 'TEE']),
    _MockModel('DeepSeek R1', '0xfed...321', false, ['LLM']),
  ];

  List<_MockModel> get _filteredModels =>
      _maxPrivacy ? _allModels.where((m) => m.isTEE).toList() : _allModels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = _filteredModels;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _maxPrivacy ? RedPillTheme.greenDark : RedPillTheme.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _maxPrivacy
                      ? RedPillTheme.green.withValues(alpha: 0.3)
                      : const Color(0xFF374151),
                ),
              ),
              child: Center(
                child: Text(
                  _maxPrivacy ? '🛡️' : '🔓',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
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
              _WalletCard(),
              const SizedBox(height: 16),

              // MAX Privacy toggle
              _PrivacyToggle(
                enabled: _maxPrivacy,
                onChanged: (val) => setState(() => _maxPrivacy = val),
              ),
              const SizedBox(height: 20),

              // Section header with count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MODELS', style: theme.textTheme.labelSmall),
                  Text(
                    '${models.length} available',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Model list
              Expanded(
                child: models.isEmpty
                    ? _EmptyState(maxPrivacy: _maxPrivacy)
                    : ListView.builder(
                        itemCount: models.length,
                        itemBuilder: (ctx, i) => _ModelTile(
                          name: models[i].name,
                          provider: models[i].provider,
                          isTEE: models[i].isTEE,
                          tags: models[i].tags,
                        ),
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

class _MockModel {
  final String name;
  final String provider;
  final bool isTEE;
  final List<String> tags;
  const _MockModel(this.name, this.provider, this.isTEE, this.tags);
}

// --- MAX Privacy Toggle ---

class _PrivacyToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PrivacyToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? RedPillTheme.greenDark : RedPillTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? RedPillTheme.green.withValues(alpha: 0.4)
                : const Color(0xFF374151),
            width: enabled ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled
                    ? RedPillTheme.green.withValues(alpha: 0.15)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  enabled ? '🛡️' : '🌐',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enabled ? 'MAX PRIVACY' : 'ALL PROVIDERS',
                    style: TextStyle(
                      color: enabled ? RedPillTheme.green : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'TEE-attested providers only — encrypted inference'
                        : 'All available models and providers',
                    style: TextStyle(
                      color: enabled
                          ? RedPillTheme.green.withValues(alpha: 0.7)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _AnimatedToggleSwitch(enabled: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _AnimatedToggleSwitch extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AnimatedToggleSwitch({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: enabled ? RedPillTheme.green : const Color(0xFF374151),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Empty state when MAX Privacy filters everything ---

class _EmptyState extends StatelessWidget {
  final bool maxPrivacy;
  const _EmptyState({required this.maxPrivacy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            maxPrivacy ? '🛡️' : '📡',
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 16),
          Text(
            maxPrivacy
                ? 'No TEE providers available'
                : 'No models available',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            maxPrivacy
                ? 'Try disabling MAX Privacy to see all providers'
                : 'Check your proxy-router connection',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Wallet Card ---

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

// --- Model Tile ---

class _ModelTile extends StatelessWidget {
  final String name;
  final String provider;
  final bool isTEE;
  final List<String> tags;

  const _ModelTile({
    required this.name,
    required this.provider,
    required this.isTEE,
    this.tags = const [],
  });

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
        subtitle: Row(
          children: [
            Text(provider, style: theme.textTheme.bodySmall),
            if (tags.isNotEmpty) ...[
              const SizedBox(width: 8),
              ...tags.take(2).map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: tag.toUpperCase() == 'TEE'
                            ? RedPillTheme.green.withValues(alpha: 0.6)
                            : const Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
            ],
          ],
        ),
        trailing: isTEE
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: RedPillTheme.greenDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: RedPillTheme.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🛡️',
                      style: TextStyle(fontSize: 10),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'TEE',
                      style: TextStyle(
                        color: RedPillTheme.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
