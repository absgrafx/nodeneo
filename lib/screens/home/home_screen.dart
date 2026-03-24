import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../app_route_observer.dart';
import '../../constants/app_brand.dart';
import '../../constants/network_tokens.dart';
import '../../services/bridge.dart';
import '../../services/model_status_api.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';
import '../../widgets/crypto_token_icons.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_transcript_screen.dart';
import '../security/security_settings_screen.dart';
import '../sessions/on_chain_sessions_screen.dart';
import '../settings/session_length_settings_screen.dart';
import '../../widgets/session_close_flow.dart';
import '../wallet/wallet_security_actions.dart';
import '../../widgets/send_token_sheet.dart';
import '../../widgets/morpheus_logo.dart';

/// Primary line for history / continue cards: saved topic, else model name.
String conversationHeadline(Map<String, dynamic> c) {
  final t = (c['title'] as String?)?.trim() ?? '';
  if (t.isNotEmpty) return t;
  return c['model_name'] as String? ?? 'Chat';
}

/// Subtitle: model, secure vs standard, session state (+ minutes left when [session_ends_at] set), relative time.
String conversationMetaLine(
  Map<String, dynamic> c,
  String Function(Map<String, dynamic>) rel,
) {
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

  const HomeScreen({
    super.key,
    this.onWalletErased,
    this.onOpenNetworkSettings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  static const int _walletBalanceDecimals = 5;

  Timer? _sessionRefreshTimer;
  bool _maxPrivacy = false;
  String _address = '';
  String _ethBalance = '—';
  String _morBalance = '—';
  bool _rpcChecking = true;
  bool? _rpcReachable;
  ModelStatusResponse? _statusApi;
  List<ModelStatusEntry> _models = [];
  bool _loadingModels = false;
  String? _modelsError;
  List<Map<String, dynamic>> _historyConvos = [];
  List<Map<String, dynamic>> _activeResumeChats = [];

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _refreshRpcReachability();
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
    _refreshRpcReachability();
    _loadModels();
  }

  Future<void> _refreshRpcReachability() async {
    if (!mounted) return;
    setState(() {
      _rpcChecking = true;
    });
    try {
      final raw = await RpcSettingsStore.instance.effectiveRpcUrl();
      final ok = await RpcEndpointValidator.anyReachable(raw);
      if (mounted) {
        setState(() {
          _rpcReachable = ok;
          _rpcChecking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _rpcReachable = false;
          _rpcChecking = false;
        });
      }
    }
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
      final active = list
          .where((m) {
            final sid = m['session_id'];
            return sid is String && sid.isNotEmpty;
          })
          .take(12)
          .toList();
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
        _ethBalance = formatWeiFixedDecimals(
          summary['eth_balance'] as String? ?? '0',
          _walletBalanceDecimals,
        );
        _morBalance = formatWeiFixedDecimals(
          summary['mor_balance'] as String? ?? '0',
          _walletBalanceDecimals,
        );
      });
    } catch (_) {}
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final resp = await fetchModelStatus();
      if (!mounted) return;
      var list = resp.models;
      if (_maxPrivacy) {
        list = list.where((m) => m.isTEE).toList();
      }
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _statusApi = resp;
        _models = list;
        _loadingModels = false;
      });
    } catch (e) {
      // Fallback: use Go bridge model list (less metadata but always works).
      try {
        final bridge = GoBridge();
        final raw = bridge.getActiveModels(teeOnly: _maxPrivacy);
        if (!mounted) return;
        final fallback = raw.map((m) {
          final map = m as Map<String, dynamic>;
          return ModelStatusEntry(
            id: map['id'] as String? ?? '',
            name: map['name'] as String? ?? 'Unknown',
            status: 'operational',
            type: (map['model_type'] as String? ?? 'LLM').toUpperCase(),
            tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
            providers: 0,
            minPriceMorHr: 0,
          );
        }).toList();
        fallback.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _statusApi = null;
          _models = fallback;
          _loadingModels = false;
        });
      } catch (fallbackErr) {
        if (!mounted) return;
        setState(() {
          _modelsError = fallbackErr.toString();
          _loadingModels = false;
        });
      }
    }
  }

  void _openModelChat(BuildContext context, ModelStatusEntry m) {
    if (m.type != 'LLM') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat is only for LLM models (this one is ${m.type}).'),
        ),
      );
      return;
    }
    if (m.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model has no id — cannot open session.')),
      );
      return;
    }
    final id = m.id;
    final name = m.name;
    final tags = m.tags;
    final isTEE = tags.any((t) => t.toUpperCase().contains('TEE'));
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(modelId: id, modelName: name, isTEE: isTEE),
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
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ConversationTranscriptScreen(
              conversationId: id,
              modelId: mid,
              modelName: name,
              isTEE: isTee,
              onChainSessionId: sid.trim().isEmpty ? null : sid.trim(),
            ),
          ),
        )
        .then((_) {
          if (mounted) _loadConversations();
        });
  }

  Future<void> _confirmDeleteConversation(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _renameConversationDialog(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
    final id = c['id'] as String? ?? '';
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: conversationHeadline(c));
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        GoBridge().setConversationTitle(
          conversationId: id,
          title: ctrl.text.trim(),
        );
        _loadConversations();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
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
  Future<void> _closeOnChainSessionForConversation(
    BuildContext context,
    Map<String, dynamic> c,
  ) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
        onCloseActiveSession: (c) =>
            _closeOnChainSessionForConversation(context, c),
        onDeleteConversation: (c) => _confirmDeleteConversation(context, c),
        onRename: (c) => _renameConversationDialog(context, c),
        onTogglePin: _togglePin,
        relativeTime: _relativeUpdated,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const MorpheusLogo(size: 34),
            const SizedBox(width: 10),
            Text(
              AppBrand.displayName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.1,
              ),
            ),
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
              } else if (value == 'session_length') {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const SessionLengthSettingsScreen(),
                  ),
                );
              } else if (value == 'sessions') {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnChainSessionsScreen(),
                  ),
                );
              } else if (value == 'security') {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const SecuritySettingsScreen(),
                  ),
                );
              } else if (value == 'export_key') {
                await showExportPrivateKeyFlow(context);
              } else if (value == 'erase_wallet') {
                await showEraseWalletFlow(
                  context,
                  onWalletErased: widget.onWalletErased,
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
                  subtitle: Text(
                    'App lock · biometrics',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'network',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_ethernet, size: 22),
                  title: Text('Network'),
                  subtitle: Text(
                    'Custom Base RPC (optional)',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'session_length',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.timer_outlined, size: 22),
                  title: Text('Session length'),
                  subtitle: Text(
                    'Default on-chain chat duration',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sessions',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.hub_outlined, size: 22),
                  title: Text('Sessions'),
                  subtitle: Text(
                    'Open on-chain inference sessions',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'export_key',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.key_outlined,
                    size: 22,
                    color: RedPillTheme.amber,
                  ),
                  title: Text('Export private key'),
                  subtitle: Text(
                    'MetaMask, Rabby, etc.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'erase_wallet',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    size: 22,
                    color: RedPillTheme.red.withValues(alpha: 0.9),
                  ),
                  title: Text(
                    'Erase wallet on this device',
                    style: TextStyle(
                      color: RedPillTheme.red.withValues(alpha: 0.95),
                    ),
                  ),
                  subtitle: const Text(
                    'Clears saved phrase; on-chain funds unchanged',
                    style: TextStyle(fontSize: 11),
                  ),
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
              Text('WALLET', style: theme.textTheme.labelSmall),
              const SizedBox(height: 8),
              _WalletCard(
                fullAddress: _address,
                ethBalance: _ethBalance,
                morBalance: _morBalance,
                rpcChecking: _rpcChecking,
                rpcReachable: _rpcReachable,
                onOpenNetworkSettings: widget.onOpenNetworkSettings,
                onSendMor: () {
                  showSendTokenSheet(
                    context,
                    sendMor: true,
                    onSent: () {
                      if (mounted) _loadWallet();
                    },
                  );
                },
                onSendEth: () {
                  showSendTokenSheet(
                    context,
                    sendMor: false,
                    onSent: () {
                      if (mounted) _loadWallet();
                    },
                  );
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
                    Icon(
                      Icons.forum_outlined,
                      size: 16,
                      color: RedPillTheme.green.withValues(alpha: 0.9),
                    ),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 11,
                    height: 1.3,
                  ),
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
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openResumeChat(context, c),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: RedPillTheme.mainPanelFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: RedPillTheme.mainPanelOutline(),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Close on-chain session',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 22,
                                    color: Colors.red.shade400,
                                  ),
                                  onPressed: () =>
                                      _closeOnChainSessionForConversation(
                                        context,
                                        c,
                                      ),
                                ),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: tee
                                        ? RedPillTheme.green.withValues(alpha: 0.18)
                                        : RedPillTheme.mainPanelFill,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: tee
                                          ? RedPillTheme.green.withValues(alpha: 0.35)
                                          : const Color(0xFF374151),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      tee ? '🛡️' : '💬',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        conversationMetaLine(
                                          c,
                                          _relativeUpdated,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF6B7280),
                                              fontSize: 10,
                                              height: 1.25,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: theme.hintColor,
                                  size: 22,
                                ),
                              ],
                            ),
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
                        : _statusApi != null
                            ? '${_models.length} across ${_statusApi!.activeProviders} providers'
                            : '${_models.length} available',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: RedPillTheme.green.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'START A NEW CHAT by selecting a model',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: RedPillTheme.green.withValues(alpha: 0.85),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (_statusApi != null)
                    Tooltip(
                      message: 'Border color shows 6-hour availability:\nGreen ≥ 99%  ·  Yellow ≥ 85%  ·  Red < 85%',
                      preferBelow: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.monitor_heart_outlined, size: 12, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Text(
                            'Availability',
                            style: TextStyle(fontSize: 10, color: theme.hintColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              Expanded(child: _buildModelList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelList() {
    if (_loadingModels) {
      return const Center(
        child: CircularProgressIndicator(color: RedPillTheme.green),
      );
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
        final m = _models[i];
        return _ModelTile(
          entry: m,
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
          color: RedPillTheme.mainPanelFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? RedPillTheme.mainPanelOutline(0.45)
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
                    ? RedPillTheme.green.withValues(alpha: 0.18)
                    : RedPillTheme.mainPanelFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled
                      ? RedPillTheme.green.withValues(alpha: 0.35)
                      : const Color(0xFF374151),
                ),
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
                          color: enabled
                              ? RedPillTheme.green
                              : const Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (!enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
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
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
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
            maxPrivacy
                ? 'No MAX Security providers available'
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
  static const double _tokenVisualSize = 44;

  final String fullAddress;
  final String ethBalance;
  final String morBalance;
  final bool rpcChecking;
  final bool? rpcReachable;
  final Future<void> Function()? onOpenNetworkSettings;
  final VoidCallback onSendMor;
  final VoidCallback onSendEth;

  const _WalletCard({
    required this.fullAddress,
    required this.ethBalance,
    required this.morBalance,
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenNetworkSettings,
    required this.onSendMor,
    required this.onSendEth,
  });

  static String _shorten(String addr) {
    if (addr.length < 12) return addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  /// Copy [IconButton] (~48) + gap + typical CONNECTED / error pill (right side of row).
  static const double _reservedNonTextWidth =
      48 + 8 + 130; // copy + gap before pill + pill reserve

  static double _measureTextWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addressStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'JetBrains Mono',
      letterSpacing: 0.35,
      fontSize: 13,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
    ) ?? const TextStyle(fontSize: 13);
    return Card(
      color: RedPillTheme.mainPanelFill,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: RedPillTheme.mainPanelOutline(), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final avail = (constraints.maxWidth - _reservedNonTextWidth)
                    .clamp(48.0, double.infinity);
                final showFull = fullAddress.isNotEmpty &&
                    _measureTextWidth(fullAddress, addressStyle) <= avail;
                final addressText = fullAddress.isEmpty
                    ? '—'
                    : (showFull ? fullAddress : _shorten(fullAddress));
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Copy full address',
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 22,
                        color: fullAddress.isEmpty
                            ? theme.disabledColor
                            : theme.colorScheme.onSurface.withValues(alpha: 0.9),
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
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
                      child: Text(
                        addressText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: addressStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: rpcChecking
                          ? 'Checking whether your Base RPC URL(s) respond…'
                          : rpcReachable == true
                              ? 'At least one configured Base RPC URL is reachable (same list the app uses).'
                              : 'No configured Base RPC URL responded. Tap to open network settings.',
                      child: _WalletRpcStatusPill(
                        rpcChecking: rpcChecking,
                        rpcReachable: rpcReachable,
                        onOpenNetworkSettings: onOpenNetworkSettings,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Click a balance to send',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BalanceChip(
                    expand: true,
                    symbol: NetworkTokens.morSymbol,
                    value: morBalance,
                    color: RedPillTheme.green,
                    helperText: AppBrand.morBalanceHelper,
                    onTap: onSendMor,
                    token: TokenWithBaseInlay(
                      token: MorTokenIcon(size: _tokenVisualSize),
                      diameter: _tokenVisualSize,
                      badgeDiameter: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BalanceChip(
                    expand: true,
                    symbol: NetworkTokens.ethSymbol,
                    value: ethBalance,
                    color: RedPillTheme.amber,
                    helperText: AppBrand.ethBalanceHelper,
                    onTap: onSendEth,
                    token: TokenWithBaseInlay(
                      token: EthTokenIcon(size: _tokenVisualSize),
                      diameter: _tokenVisualSize,
                      badgeDiameter: 17,
                    ),
                  ),
                ),
              ],
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
    final drawerWidth = min(420.0, MediaQuery.sizeOf(context).width * 0.92);
    return Drawer(
      width: drawerWidth,
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chats & Sessions',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a row to open history. Swipe right to pin · swipe left for close session (if open) or delete. '
                    'Rename with the pencil.',
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
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: theme.hintColor,
                ),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : _HistoryConversationList(
                      theme: theme,
                      conversations: conversations,
                      onOpenTranscript: onOpenTranscript,
                      onCloseActiveSession: onCloseActiveSession,
                      onDeleteConversation: onDeleteConversation,
                      onRename: onRename,
                      onTogglePin: onTogglePin,
                      relativeTime: relativeTime,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single list: pinned rows first (SQLite order), pin icon only — no section headers.
class _HistoryConversationList extends StatelessWidget {
  final ThemeData theme;
  final List<Map<String, dynamic>> conversations;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  const _HistoryConversationList({
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: conversations.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
      itemBuilder: (ctx, i) {
        final c = conversations[i];
        return _HistoryConversationTile(
          theme: theme,
          c: c,
          onOpenTranscript: onOpenTranscript,
          onCloseActiveSession: onCloseActiveSession,
          onDeleteConversation: onDeleteConversation,
          onRename: onRename,
          onTogglePin: onTogglePin,
          relativeTime: relativeTime,
        );
      },
    );
  }
}

class _HistoryConversationTile extends StatelessWidget {
  const _HistoryConversationTile({
    required this.theme,
    required this.c,
    required this.onOpenTranscript,
    required this.onCloseActiveSession,
    required this.onDeleteConversation,
    required this.onRename,
    required this.onTogglePin,
    required this.relativeTime,
  });

  final ThemeData theme;
  final Map<String, dynamic> c;
  final void Function(Map<String, dynamic> c) onOpenTranscript;
  final void Function(Map<String, dynamic> c) onCloseActiveSession;
  final void Function(Map<String, dynamic> c) onDeleteConversation;
  final void Function(Map<String, dynamic> c) onRename;
  final void Function(Map<String, dynamic> c) onTogglePin;
  final String Function(Map<String, dynamic> c) relativeTime;

  @override
  Widget build(BuildContext context) {
    final headline = conversationHeadline(c);
    final cid = c['id'] as String? ?? '';
    final sid = c['session_id'];
    final hasSession = sid is String && sid.isNotEmpty;
    final isPinned = c['pinned'] == true;
    final showPinIcon = isPinned;
    final isTee = c['is_tee'] == true;
    return Slidable(
      key: ValueKey('drawer-$cid'),
      groupTag: 'history-drawer',
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => onTogglePin(c),
            backgroundColor: Colors.amber.shade800,
            foregroundColor: Colors.white,
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: hasSession ? 0.44 : 0.22,
        children: [
          if (hasSession)
            SlidableAction(
              onPressed: (_) => onCloseActiveSession(c),
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              icon: Icons.link_off_rounded,
              label: 'Close',
            ),
          SlidableAction(
            onPressed: (_) => onDeleteConversation(c),
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          hasSession ? Icons.play_circle_outline : Icons.history,
          color: hasSession
              ? RedPillTheme.green.withValues(alpha: 0.9)
              : theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        title: Row(
          children: [
            if (showPinIcon) ...[
              Icon(Icons.push_pin, size: 15, color: Colors.amber.shade600),
              const SizedBox(width: 6),
            ],
            if (isTee) ...[
              const Text('🛡️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            conversationMetaLine(c, relativeTime),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.3),
          ),
        ),
        trailing: IconButton(
          tooltip: 'Rename topic',
          icon: Icon(Icons.edit_outlined, color: theme.hintColor, size: 22),
          onPressed: () => onRename(c),
        ),
        onTap: () {
          Navigator.pop(context);
          onOpenTranscript(c);
        },
      ),
    );
  }
}

/// JSON-RPC reachability for the same URL list [RpcSettingsStore.effectiveRpcUrl] uses (not a live socket to Go).
class _WalletRpcStatusPill extends StatelessWidget {
  final bool rpcChecking;
  final bool? rpcReachable;
  final Future<void> Function()? onOpenNetworkSettings;

  const _WalletRpcStatusPill({
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenNetworkSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rpcChecking) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'RPC…',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                fontSize: 9,
              ),
            ),
          ],
        ),
      );
    }
    final ok = rpcReachable == true;
    final borderColor = ok
        ? RedPillTheme.green.withValues(alpha: 0.35)
        : RedPillTheme.red.withValues(alpha: 0.45);
    final bg = ok ? RedPillTheme.mainPanelFill : const Color(0xFF1F1518);
    final fg = ok
        ? RedPillTheme.green
        : RedPillTheme.red.withValues(alpha: 0.95);
    final label = ok ? 'CONNECTED' : 'NO RPC';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: !ok && onOpenNetworkSettings != null
            ? () => onOpenNetworkSettings!()
            : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String symbol;
  final String value;
  final Color color;
  final String? helperText;
  final Widget token;
  final VoidCallback onTap;
  final bool expand;

  const _BalanceChip({
    required this.symbol,
    required this.value,
    required this.color,
    required this.token,
    required this.onTap,
    this.helperText,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: RedPillTheme.mainPanelFill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
    );
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          symbol,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        if (helperText != null && helperText!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helperText!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 9,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                token,
                const SizedBox(width: 10),
                if (expand)
                  Expanded(child: textColumn)
                else
                  Flexible(child: textColumn),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Model Tile ---

class _ModelTile extends StatelessWidget {
  final ModelStatusEntry entry;
  final VoidCallback onTap;

  const _ModelTile({required this.entry, required this.onTap});

  static Color _healthColor(double? pct) {
    if (pct == null) return RedPillTheme.mainPanelOutline();
    if (pct >= 99.0) return RedPillTheme.green;
    if (pct >= 85.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTEE = entry.isTEE;
    final price = entry.formattedPrice;
    final borderColor = _healthColor(entry.uptime6h);

    return Card(
      color: RedPillTheme.mainPanelFill,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor.withValues(alpha: 0.55), width: 1.3),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // --- Icon ---
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isTEE
                      ? RedPillTheme.green.withValues(alpha: 0.18)
                      : RedPillTheme.mainPanelFill,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isTEE
                        ? RedPillTheme.green.withValues(alpha: 0.35)
                        : const Color(0xFF374151),
                  ),
                ),
                child: Center(
                  child: Text(isTEE ? '🛡️' : '🤖', style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),

              // --- Left: name · type · tags ---
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (entry.type.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text('·', style: TextStyle(color: theme.hintColor, fontSize: 12)),
                      ),
                      Text(
                        entry.type,
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                    ...entry.tags
                        .where((t) => t.toLowerCase() != entry.type.toLowerCase())
                        .take(2)
                        .map((tag) => Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  color: tag.toLowerCase() == 'tee'
                                      ? RedPillTheme.green.withValues(alpha: 0.7)
                                      : const Color(0xFF6B7280),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )),
                  ],
                ),
              ),

              // --- Right: price · providers ---
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (price != null)
                    Text(price, style: TextStyle(fontSize: 10, color: theme.hintColor)),
                  if (price != null && entry.providers > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·', style: TextStyle(color: theme.hintColor, fontSize: 10)),
                    ),
                  if (entry.providers > 0) ...[
                    Icon(Icons.dns_outlined, size: 11, color: theme.hintColor),
                    const SizedBox(width: 2),
                    Text(
                      '${entry.providers}',
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
