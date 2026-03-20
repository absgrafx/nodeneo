import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_route_observer.dart';
import '../../services/bridge.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_transcript_screen.dart';
import '../security/security_settings_screen.dart';
import '../../widgets/session_close_flow.dart';
import '../wallet/wallet_tools_screen.dart';

/// Primary line for history / continue cards: saved topic, else model name.
String conversationHeadline(Map<String, dynamic> c) {
  final t = (c['title'] as String?)?.trim() ?? '';
  if (t.isNotEmpty) return t;
  return c['model_name'] as String? ?? 'Chat';
}

/// Subtitle: model, secure vs standard, session state (+ minutes left when [session_ends_at] set), relative time.
String conversationMetaLine(Map<String, dynamic> c, String Function(Map<String, dynamic>) rel) {
  final model = c['model_name'] as String? ?? 'Model';
  final tee = c['is_tee'] == true;
  final sid = c['session_id'];
  final hasSession = sid is String && sid.isNotEmpty;
  final endsAt = (c['session_ends_at'] as num?)?.toInt();
  final String sessionBit;
  if (!hasSession) {
    sessionBit = 'Session closed';
  } else if (endsAt != null && endsAt > 0) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = endsAt - nowSec;
    if (left <= 0) {
      sessionBit = 'Session ended';
    } else {
      final minutes = (left + 59) ~/ 60;
      sessionBit = minutes <= 1 ? '~1 min left' : '~$minutes min left';
    }
  } else {
    sessionBit = 'On-chain open';
  }
  return '$model · ${tee ? 'Secure' : 'Standard'} · $sessionBit · ${rel(c)}';
}

class HomeScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;
  final Future<void> Function()? onOpenNetworkSettings;

  const HomeScreen({super.key, this.onWalletErased, this.onOpenNetworkSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  Timer? _sessionRefreshTimer;
  bool _maxPrivacy = false;
  String _address = '';
  String _ethBalance = '—';
  String _morBalance = '—';
  List<dynamic> _models = [];
  bool _loadingModels = false;
  String? _modelsError;
  List<Map<String, dynamic>> _historyConvos = [];
  List<Map<String, dynamic>> _activeResumeChats = [];

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadModels();
    _loadConversations();
    // Re-fetch unclosed sessions + reconcile expired / closed (chain + wall clock).
    _sessionRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) _loadConversations();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      redpillRouteObserver.unsubscribe(this);
      redpillRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    redpillRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadConversations();
    _loadWallet();
    _loadModels();
  }

  /// Conversations: SQLite order is pinned first, then updated_at (see Go ListConversations).
  void _loadConversations() {
    try {
      final bridge = GoBridge();
      final raw = bridge.getConversations();
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
      final active = list.where((m) {
        final sid = m['session_id'];
        return sid is String && sid.isNotEmpty;
      }).take(12).toList();
      if (mounted) {
        setState(() {
          _historyConvos = list;
          _activeResumeChats = active;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyConvos = [];
          _activeResumeChats = [];
        });
      }
    }
  }

  String _relativeUpdated(Map<String, dynamic> c) {
    final u = (c['updated_at'] as num?)?.toInt();
    if (u == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(u * 1000);
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.month}/${t.day}';
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
      if (mounted) {
        _loadWallet();
        _loadConversations();
      }
    });
  }

  void _openResumeChat(BuildContext context, Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    final mid = c['model_id'] as String? ?? '';
    final name = c['model_name'] as String? ?? 'Chat';
    final sid = c['session_id'] as String? ?? '';
    final isTee = c['is_tee'] == true;
    if (id.isEmpty || mid.isEmpty || sid.isEmpty) return;
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          modelId: mid,
          modelName: name,
          isTEE: isTee,
          resumeConversationId: id,
          resumeSessionId: sid,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        _loadWallet();
        _loadConversations();
      }
    });
  }

  void _openTranscript(BuildContext context, Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    final mid = c['model_id'] as String? ?? '';
    final name = c['model_name'] as String? ?? 'Chat';
    final isTee = c['is_tee'] == true;
    final sid = c['session_id'] as String? ?? '';
    if (id.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationTranscriptScreen(
          conversationId: id,
          modelId: mid,
          modelName: name,
          isTEE: isTee,
          onChainSessionId: sid.trim().isEmpty ? null : sid.trim(),
        ),
      ),
    ).then((_) {
      if (mounted) _loadConversations();
    });
  }

  Future<void> _confirmDeleteConversation(BuildContext context, Map<String, dynamic> c) async {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'Removes this thread from this device and submits an on-chain close if a session is still open '
          '(same as ✕ — stake returns per contract rules). If the network refuses the close, the thread '
          'is still removed locally and you can retry from Network / Open on-chain sessions.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = GoBridge().deleteConversation(id);
      _loadConversations();
      final warn = res['close_warning'] as String?;
      if (context.mounted && warn != null && warn.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conversation removed locally. On-chain close failed — check Open on-chain sessions or retry.\n$warn',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _renameConversationDialog(BuildContext context, Map<String, dynamic> c) async {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: conversationHeadline(c));
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename thread'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Topic title',
              hintText: 'Shown in history — model stays in subtitle',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (ok == true && mounted) {
        try {
          GoBridge().setConversationTitle(conversationId: id, title: ctrl.text.trim());
          _loadConversations();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      }
    } finally {
      ctrl.dispose();
    }
  }

  void _togglePin(Map<String, dynamic> c) {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    try {
      final next = c['pinned'] != true;
      GoBridge().setConversationPinned(conversationId: id, pinned: next);
      _loadConversations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Close on-chain session for this thread; Go clears SQLite session_id on success.
  Future<void> _closeOnChainSessionForConversation(BuildContext context, Map<String, dynamic> c) async {
    final sid = c['session_id'] as String? ?? '';
    if (sid.isEmpty) return;
    final ok = await confirmCloseOnChainSession(context);
    if (ok != true || !mounted || !context.mounted) return;
    try {
      await runCloseOnChainSessionFlow(context, sid);
      if (!mounted) return;
      _loadConversations();
    } on GoBridgeException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: _HistoryChatsDrawer(
        theme: theme,
        conversations: _historyConvos,
        onOpenTranscript: (c) => _openTranscript(context, c),
        onCloseActiveSession: (c) => _closeOnChainSessionForConversation(context, c),
        onDeleteConversation: (c) => _confirmDeleteConversation(context, c),
        onRename: (c) => _renameConversationDialog(context, c),
        onTogglePin: _togglePin,
        relativeTime: _relativeUpdated,
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
                _loadConversations();
              } else if (value == 'network') {
                final cb = widget.onOpenNetworkSettings;
                if (cb != null) await cb();
              } else if (value == 'security') {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SecuritySettingsScreen()),
                );
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
                value: 'security',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline, size: 22),
                  title: Text('Security'),
                  subtitle: Text('App lock · biometrics', style: TextStyle(fontSize: 11)),
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
              if (_activeResumeChats.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 16, color: RedPillTheme.green.withValues(alpha: 0.9)),
                    const SizedBox(width: 8),
                    Text(
                      'CONTINUE CHATTING',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: RedPillTheme.green.withValues(alpha: 0.85),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to resume. Use ✕ to close on-chain (same as reclaim flow).',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11, height: 1.3),
                ),
                const SizedBox(height: 10),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _activeResumeChats.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final c = _activeResumeChats[i];
                    final name = conversationHeadline(c);
                    final tee = c['is_tee'] == true;
                    return Material(
                      color: RedPillTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openResumeChat(context, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Close on-chain session',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                icon: Icon(Icons.close_rounded, size: 22, color: Colors.red.shade400),
                                onPressed: () => _closeOnChainSessionForConversation(context, c),
                              ),
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: tee ? RedPillTheme.greenDark : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: tee
                                        ? RedPillTheme.green.withValues(alpha: 0.35)
                                        : const Color(0xFF374151),
                                  ),
                                ),
                                child: Center(child: Text(tee ? '🛡️' : '💬', style: const TextStyle(fontSize: 16))),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      conversationMetaLine(c, _relativeUpdated),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFF6B7280),
                                        fontSize: 10,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (tee)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
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
                                      Text(
                                        'SECURE',
                                        style: TextStyle(
                                          color: RedPillTheme.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Icon(Icons.chevron_right, color: theme.hintColor, size: 22),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
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
        final modelType = (m['model_type'] as String? ?? 'LLM').toUpperCase();
        return _ModelTile(
          name: m['name'] as String? ?? 'Unknown',
          modelType: modelType,
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
                                'Secure available',
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
                        ? 'MAX Security providers only — hardware-attested inference'
                        : 'Enable for MAX Security (hardware-attested) inference',
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
            maxPrivacy ? 'No MAX Security providers available' : 'No models available',
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

/// Drawer: local SQLite chat history (on-chain open/close + close action inline).
class _HistoryChatsDrawer extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> conversations;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  const _HistoryChatsDrawer({
    required this.theme,
    required this.conversations,
    required this.onOpenTranscript,
    required this.onCloseActiveSession,
    required this.onDeleteConversation,
    required this.onRename,
    required this.onTogglePin,
    required this.relativeTime,
  });

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
                  Text('Chats & Sessions', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a topic for history, then Continue chatting. Pin favorites. '
                    '✕ closes on-chain; 🗑 deletes locally and closes on-chain if a session is open.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'LOCAL HISTORY',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.8, color: theme.hintColor),
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No saved conversations yet.\nOpen a model to start chatting.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: conversations.length,
                      separatorBuilder: (context, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final c = conversations[i];
                        final headline = conversationHeadline(c);
                        final sid = c['session_id'];
                        final hasSession = sid is String && sid.isNotEmpty;
                        final pinned = c['pinned'] == true;
                        return ListTile(
                          leading: Icon(
                            hasSession ? Icons.play_circle_outline : Icons.history,
                            color: hasSession
                                ? RedPillTheme.green.withValues(alpha: 0.9)
                                : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                          title: Text(headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            conversationMetaLine(c, relativeTime),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, height: 1.25),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasSession)
                                IconButton(
                                  tooltip: 'Close on-chain session',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                  icon: Icon(Icons.close_rounded, size: 20, color: Colors.red.shade400),
                                  onPressed: () => onCloseActiveSession(c),
                                ),
                              IconButton(
                                tooltip: pinned ? 'Unpin' : 'Pin to top',
                                icon: Icon(
                                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                  size: 20,
                                  color: pinned ? Colors.amber.shade600 : theme.hintColor,
                                ),
                                onPressed: () => onTogglePin(c),
                              ),
                              IconButton(
                                tooltip: 'Delete conversation',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                icon: Icon(Icons.delete_outline_rounded, size: 20, color: theme.hintColor),
                                onPressed: () => onDeleteConversation(c),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: theme.hintColor, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                onSelected: (v) {
                                  if (v == 'rename') onRename(c);
                                  if (v == 'delete') onDeleteConversation(c);
                                },
                                itemBuilder: (mctx) => [
                                  const PopupMenuItem(value: 'rename', child: Text('Rename topic')),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete conversation'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            onOpenTranscript(c);
                          },
                        );
                      },
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
  final String modelType;
  final bool isTEE;
  final List<String> tags;
  final VoidCallback onTap;

  const _ModelTile({
    required this.name,
    required this.modelType,
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
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (modelType.isNotEmpty)
                Text(
                  modelType,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ...tags.take(4).map(
                    (tag) => Text(
                      tag,
                      style: TextStyle(
                        color: tag.toUpperCase() == 'TEE'
                            ? RedPillTheme.green.withValues(alpha: 0.6)
                            : const Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            ],
          ),
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
                    Text('SECURE', style: TextStyle(color: RedPillTheme.green, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
