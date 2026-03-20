import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bridge.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';
import '../chat/chat_screen.dart';
import '../sessions/on_chain_sessions_screen.dart';
import '../wallet/wallet_tools_screen.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;
  final Future<void> Function()? onOpenNetworkSettings;

  const HomeScreen({super.key, this.onWalletErased, this.onOpenNetworkSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _maxPrivacy = false;
  String _address = '';
  String _ethBalance = '—';
  String _morBalance = '—';
  List<dynamic> _models = [];
  bool _loadingModels = false;
  String? _modelsError;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadModels();
  }

  void _loadWallet() {
    try {
      final bridge = GoBridge();
      final summary = bridge.getWalletSummary();
      setState(() {
        _address = summary['address'] as String? ?? '';
        _ethBalance = formatWeiAsEthDecimal(summary['eth_balance'] as String? ?? '0');
        _morBalance = formatWeiFixedDecimals(summary['mor_balance'] as String? ?? '0', 2);
      });
    } catch (_) {}
  }

  void _loadModels() {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final bridge = GoBridge();
      final models = bridge.getActiveModels(teeOnly: _maxPrivacy);
      setState(() {
        _models = models;
        _loadingModels = false;
      });
    } on GoBridgeException catch (e) {
      setState(() {
        _modelsError = e.message;
        _loadingModels = false;
      });
    } catch (e) {
      setState(() {
        _modelsError = e.toString();
        _loadingModels = false;
      });
    }
  }

  String _shortenAddress(String addr) {
    if (addr.length < 12) return addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  void _openOnChainSessions(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const OnChainSessionsScreen()),
    );
  }

  void _openModelChat(BuildContext context, Map<String, dynamic> m) {
    final type = (m['model_type'] as String? ?? 'LLM').toUpperCase();
    if (type != 'LLM') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chat is only for LLM models (this one is $type).')),
      );
      return;
    }
    final id = m['id'] as String? ?? '';
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model has no id — cannot open session.')),
      );
      return;
    }
    final name = m['name'] as String? ?? 'Model';
    final tags = (m['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final isTEE = tags.any((t) => t.toUpperCase().contains('TEE'));
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          modelId: id,
          modelName: name,
          isTEE: isTEE,
        ),
      ),
    )
        .then((_) {
      if (mounted) _loadWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: _HistoryChatsDrawer(
        theme: theme,
        onOpenOnChainSessions: () => _openOnChainSessions(context),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: true,
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
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz, size: 24),
            onSelected: (value) async {
              if (value == 'refresh') {
                _loadWallet();
                _loadModels();
              } else if (value == 'network') {
                final cb = widget.onOpenNetworkSettings;
                if (cb != null) await cb();
              } else if (value == 'sessions') {
                _openOnChainSessions(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, size: 22),
                  title: Text('Refresh'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'network',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_ethernet, size: 22),
                  title: Text('Network / RPC'),
                  subtitle: Text('Optional custom Base endpoint', style: TextStyle(fontSize: 11)),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sessions',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.hub_outlined, size: 22),
                  title: Text('Open on-chain sessions'),
                  subtitle: Text('Close early · reclaim stake', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WalletCard(
                fullAddress: _address,
                ethBalance: _ethBalance,
                morBalance: _morBalance,
                onManageWallet: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => WalletToolsScreen(onWalletErased: widget.onWalletErased),
                    ),
                  ).then((_) {
                    if (mounted) _loadWallet();
                  });
                },
              ),
              const SizedBox(height: 16),

              _PrivacyToggle(
                enabled: _maxPrivacy,
                onChanged: (val) {
                  setState(() => _maxPrivacy = val);
                  _loadModels();
                },
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MODELS', style: theme.textTheme.labelSmall),
                  Text(
                    _loadingModels
                        ? 'loading...'
                        : '${_models.length} available',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Expanded(
                child: _buildModelList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: RedPillTheme.green,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
    );
  }

  Widget _buildModelList() {
    if (_loadingModels) {
      return const Center(child: CircularProgressIndicator(color: RedPillTheme.green));
    }
    if (_modelsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Could not load models',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _modelsError!,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_models.isEmpty) {
      return _EmptyState(maxPrivacy: _maxPrivacy);
    }
    return ListView.builder(
      itemCount: _models.length,
      itemBuilder: (ctx, i) {
        final m = _models[i] as Map<String, dynamic>;
        final tags = (m['tags'] as List<dynamic>?)?.cast<String>() ?? [];
        final isTEE = tags.any((t) => t.toUpperCase().contains('TEE'));
        return _ModelTile(
          name: m['name'] as String? ?? 'Unknown',
          owner: _shortenAddress(m['owner'] as String? ?? ''),
          isTEE: isTEE,
          tags: tags,
          onTap: () => _openModelChat(ctx, m),
        );
      },
    );
  }
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
                  Row(
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
                      if (!enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF374151)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🛡️', style: TextStyle(fontSize: 9)),
                              SizedBox(width: 3),
                              Text(
                                'TEE available',
                                style: TextStyle(color: Color(0xFF6B7280), fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'TEE-attested providers only — encrypted inference'
                        : 'Enable for TEE-only encrypted inference',
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

// --- Empty state ---

class _EmptyState extends StatelessWidget {
  final bool maxPrivacy;
  const _EmptyState({required this.maxPrivacy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(maxPrivacy ? '🛡️' : '📡', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            maxPrivacy ? 'No TEE providers available' : 'No models available',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            maxPrivacy
                ? 'Try disabling MAX Privacy to see all providers'
                : 'Check your network connection',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// --- Wallet Card ---

class _WalletCard extends StatelessWidget {
  final String fullAddress;
  final String ethBalance;
  final String morBalance;
  final VoidCallback onManageWallet;

  const _WalletCard({
    required this.fullAddress,
    required this.ethBalance,
    required this.morBalance,
    required this.onManageWallet,
  });

  static String _shorten(String addr) {
    if (addr.length < 12) return addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = fullAddress.isEmpty ? '—' : _shorten(fullAddress);
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
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.only(right: 4, top: 0, bottom: 0),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              tooltip: 'Copy full address',
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 22,
                                color: fullAddress.isEmpty
                                    ? theme.disabledColor
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                              ),
                              onPressed: fullAddress.isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(ClipboardData(text: fullAddress));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Wallet address copied'),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  display,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _BalanceChip(label: 'MOR', value: morBalance, color: RedPillTheme.green),
                            _BalanceChip(label: 'ETH', value: ethBalance, color: RedPillTheme.amber),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: Material(
                      color: RedPillTheme.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: onManageWallet,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                          child: Center(
                            child: Text(
                              'Manage',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: RedPillTheme.green,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drawer: on-chain sessions entry + chat history (placeholder).
class _HistoryChatsDrawer extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onOpenOnChainSessions;

  const _HistoryChatsDrawer({required this.theme, required this.onOpenOnChainSessions});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chats & sessions', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Open Morpheus sessions live on Base. Close early to reclaim stake.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.hub_outlined, color: RedPillTheme.green.withValues(alpha: 0.9)),
              title: const Text('Open on-chain sessions'),
              subtitle: const Text('List · close · reclaim MOR stake'),
              onTap: () {
                Navigator.pop(context);
                onOpenOnChainSessions();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    title: const Text('Chat history'),
                    subtitle: const Text('Placeholder — local SQLite list coming soon'),
                  ),
                ],
              ),
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
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
  final String owner;
  final bool isTEE;
  final List<String> tags;
  final VoidCallback onTap;

  const _ModelTile({
    required this.name,
    required this.owner,
    required this.isTEE,
    required this.onTap,
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
            child: Text(isTEE ? '🛡️' : '🤖', style: const TextStyle(fontSize: 18)),
          ),
        ),
        title: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
        subtitle: Row(
          children: [
            Text(owner, style: theme.textTheme.bodySmall),
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
                    Text('🛡️', style: TextStyle(fontSize: 10)),
                    SizedBox(width: 3),
                    Text('TEE', style: TextStyle(color: RedPillTheme.green, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
