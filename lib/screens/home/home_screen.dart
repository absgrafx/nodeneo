import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../app_route_observer.dart';
import '../../constants/app_brand.dart';
import '../../constants/network_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/bridge.dart';
import '../../services/model_status_api.dart';
import '../../services/platform_caps.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../theme.dart';
import '../../utils/token_amount.dart';
import '../../widgets/crypto_token_icons.dart';
import '../chat/chat_screen.dart';
import '../chat/conversation_transcript_screen.dart';
import '../settings/about_screen.dart';
import '../settings/expert_screen.dart';
import '../settings/backup_reset_screen.dart';
import '../settings/sessions_screen.dart';
import '../settings/wallet_screen.dart';
import '../../widgets/session_close_flow.dart';
import '../../widgets/send_token_sheet.dart';


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
  final Future<void> Function()? onRpcChanged;
  final Future<void> Function()? onFactoryReset;

  const HomeScreen({
    super.key,
    this.onWalletErased,
    this.onRpcChanged,
    this.onFactoryReset,
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
  String _rawEthWei = '0';
  String _rawMorWei = '0';
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
      neoRouteObserver.unsubscribe(this);
      neoRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    neoRouteObserver.unsubscribe(this);
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

  static final BigInt _minEthWei = BigInt.parse('1000000000000000'); // 0.001 ETH
  static final BigInt _minMorWei = BigInt.parse('5000000000000000000'); // 5 MOR

  bool get _walletUnfunded {
    final eth = BigInt.tryParse(_rawEthWei) ?? BigInt.zero;
    final mor = BigInt.tryParse(_rawMorWei) ?? BigInt.zero;
    return eth < _minEthWei || mor < _minMorWei;
  }

  Future<void> _loadWallet() async {
    try {
      final summary = await compute(
        (_) => GoBridge().getWalletSummary(),
        null,
      );
      if (!mounted) return;
      final rawEth = summary['eth_balance'] as String? ?? '0';
      final rawMor = summary['mor_balance'] as String? ?? '0';
      setState(() {
        _address = summary['address'] as String? ?? '';
        _rawEthWei = rawEth;
        _rawMorWei = rawMor;
        _ethBalance = formatWeiFixedDecimals(rawEth, _walletBalanceDecimals);
        _morBalance = formatWeiFixedDecimals(rawMor, _walletBalanceDecimals);
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
          '(same as close — stake returns per contract rules). If the network refuses the close, the thread '
          'is still removed locally and you can retry from Settings > Wallet.',
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
              'Conversation removed locally. On-chain close failed — check Wallet in Settings or retry.\n$warn',
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

  Future<void> _onSettingsTap(BuildContext context, String key) async {
    Navigator.of(context).pop(); // close the drawer first
    if (key == 'sessions') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const SessionsScreen(),
        ),
      );
    } else if (key == 'wallet') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const WalletScreen(),
        ),
      );
    } else if (key == 'expert') {
      final rpcChanged = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const ExpertScreen(),
        ),
      );
      if (rpcChanged == true) {
        await widget.onRpcChanged?.call();
      }
    } else if (key == 'backup') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BackupResetScreen(
            onWalletErased: widget.onWalletErased,
            onFactoryReset: widget.onFactoryReset,
          ),
        ),
      );
    } else if (key == 'about') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AboutScreen(),
        ),
      );
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
      endDrawer: _SettingsDrawer(
        theme: theme,
        onTap: (key) => _onSettingsTap(context, key),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        toolbarHeight: 72,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/wordmark_v2.png',
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 2),
            Text(
              AppBrand.tagline,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
                color: NeoTheme.emerald.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          if (PlatformCaps.isDesktop)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 22),
              onPressed: () {
                _loadWallet();
                _loadModels();
                _loadConversations();
              },
            ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.more_horiz, size: 24),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: NeoTheme.green,
          onRefresh: () async {
            _loadWallet();
            _loadModels();
            _loadConversations();
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WalletCard(
                        fullAddress: _address,
                        ethBalance: _ethBalance,
                        morBalance: _morBalance,
                        rpcChecking: _rpcChecking,
                        rpcReachable: _rpcReachable,
                        onOpenExpert: () async {
                          final rpcChanged = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => const ExpertScreen(),
                            ),
                          );
                          if (rpcChanged == true) {
                            await widget.onRpcChanged?.call();
                          }
                        },
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
                    ],
                  ),
                ),

              if (_walletUnfunded) ...[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FundWalletOverlay(address: _address),
                ),
              ] else ...[
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              color: NeoTheme.green.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CONTINUE CHATTING',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: NeoTheme.green.withValues(alpha: 0.85),
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
                                    color: NeoTheme.mainPanelFill,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: NeoTheme.mainPanelOutline(),
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
                                                ? NeoTheme.green.withValues(alpha: 0.18)
                                                : NeoTheme.mainPanelFill,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: tee
                                                  ? NeoTheme.green.withValues(alpha: 0.35)
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
                            color: NeoTheme.green.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'START A NEW CHAT by selecting a model',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: NeoTheme.green.withValues(alpha: 0.85),
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
                    ],
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: _buildModelList(),
                ),
              ],
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }

  Widget _buildModelList() {
    if (_loadingModels) {
      return const Center(
        child: CircularProgressIndicator(color: NeoTheme.green),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enabled ? '🛡️' : '🛡️',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  enabled ? 'FULL PRIVACY MODELS' : 'Full Privacy Models',
                  style: TextStyle(
                    color: enabled ? NeoTheme.green : const Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://tech.mor.org/tee.html'),
              mode: LaunchMode.externalApplication,
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: NeoTheme.green.withValues(alpha: enabled ? 0.7 : 0.4),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: _AnimatedToggleSwitch(enabled: enabled, onChanged: onChanged),
          ),
        ],
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
          color: enabled ? NeoTheme.green : const Color(0xFF374151),
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

// --- Fund Wallet Overlay ---

class _FundWalletOverlay extends StatelessWidget {
  final String address;
  const _FundWalletOverlay({required this.address});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: NeoTheme.mainPanelFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NeoTheme.amber.withValues(alpha: 0.35),
              width: 1.3,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NeoTheme.amber.withValues(alpha: 0.10),
                  border: Border.all(
                    color: NeoTheme.amber.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.account_balance_wallet_outlined,
                      size: 28, color: NeoTheme.amber),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Fund Your Wallet to Start',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: NeoTheme.amber,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Send at least 5 MOR and 0.001 ETH (Arbitrum) to your wallet address to begin using AI inference.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        address.isEmpty ? '—' : address,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: Color(0xFFF9FAFB),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy address',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.all(6),
                      ),
                      onPressed: address.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: address));
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Wallet address copied'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FundRequirement(
                    label: 'MOR',
                    amount: '≥ 5',
                    color: NeoTheme.green,
                  ),
                  const SizedBox(width: 20),
                  _FundRequirement(
                    label: 'ETH',
                    amount: '≥ 0.001',
                    color: NeoTheme.ethBlue,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Models will appear here once your wallet is funded.\nPull to refresh or tap ⋯ → Refresh.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FundRequirement extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  const _FundRequirement({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$amount $label',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}

// --- Wallet Card ---

class _WalletCard extends StatefulWidget {
  final String fullAddress;
  final String ethBalance;
  final String morBalance;
  final bool rpcChecking;
  final bool? rpcReachable;
  final Future<void> Function()? onOpenExpert;
  final VoidCallback onSendMor;
  final VoidCallback onSendEth;

  const _WalletCard({
    required this.fullAddress,
    required this.ethBalance,
    required this.morBalance,
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenExpert,
    required this.onSendMor,
    required this.onSendEth,
  });

  static String _shorten(String addr) {
    if (addr.length < 12) return addr;
    return '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';
  }

  @override
  State<_WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<_WalletCard>
    with SingleTickerProviderStateMixin {
  static const double _tokenVisualSize = 44;

  late bool _expanded;
  late AnimationController _ctrl;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _expanded = false;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: _expanded ? 1.0 : 0.0,
    );
    _heightFactor = _ctrl.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _expanded ? _ctrl.forward() : _ctrl.reverse();
    });
  }

  static const double _reservedNonTextWidth = 48 + 8 + 130;

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

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, expandedBody) {
        return Card(
          color: NeoTheme.mainPanelFill,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: NeoTheme.mainPanelOutline(), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — always visible, tappable to toggle
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Copy full address',
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: widget.fullAddress.isEmpty
                              ? theme.disabledColor
                              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: widget.fullAddress.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: widget.fullAddress));
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
                          widget.fullAddress.isEmpty
                              ? '—'
                              : _WalletCard._shorten(widget.fullAddress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: addressStyle.copyWith(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.morBalance,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: NeoTheme.green.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        ' MOR',
                        style: TextStyle(fontSize: 10, color: NeoTheme.green.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.ethBalance,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: NeoTheme.ethBlue.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        ' ETH',
                        style: TextStyle(fontSize: 10, color: NeoTheme.ethBlue.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(width: 4),
                      RotationTransition(
                        turns: _ctrl.drive(
                          Tween<double>(begin: 0.0, end: 0.5)
                              .chain(CurveTween(curve: Curves.easeInOut)),
                        ),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: NeoTheme.platinum.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded body — animated
              ClipRect(
                child: Align(
                  heightFactor: _heightFactor.value,
                  alignment: Alignment.topCenter,
                  child: expandedBody,
                ),
              ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final avail = (constraints.maxWidth - _reservedNonTextWidth)
                    .clamp(48.0, double.infinity);
                final showFull = widget.fullAddress.isNotEmpty &&
                    _measureTextWidth(widget.fullAddress, addressStyle) <= avail;
                final addressText = widget.fullAddress.isEmpty
                    ? '—'
                    : (showFull ? widget.fullAddress : _WalletCard._shorten(widget.fullAddress));
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
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
                      message: widget.rpcChecking
                          ? 'Checking whether your Base RPC URL(s) respond...'
                          : widget.rpcReachable == true
                              ? 'At least one configured Base RPC URL is reachable (same list the app uses).'
                              : 'No configured Base RPC URL responded. Tap to open Expert settings.',
                      child: _WalletRpcStatusPill(
                        rpcChecking: widget.rpcChecking,
                        rpcReachable: widget.rpcReachable,
                        onOpenExpert: widget.onOpenExpert,
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
                    value: widget.morBalance,
                    color: NeoTheme.green,
                    helperText: AppBrand.morBalanceHelper,
                    onTap: widget.onSendMor,
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
                    value: widget.ethBalance,
                    color: NeoTheme.ethBlue,
                    helperText: AppBrand.ethBalanceHelper,
                    onTap: widget.onSendEth,
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
    final isApi = c['source'] == 'api';
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
              ? NeoTheme.green.withValues(alpha: 0.9)
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
            if (isApi) ...[
              Icon(Icons.smart_toy_outlined, size: 15, color: NeoTheme.green.withValues(alpha: 0.7)),
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
  final Future<void> Function()? onOpenExpert;

  const _WalletRpcStatusPill({
    required this.rpcChecking,
    required this.rpcReachable,
    required this.onOpenExpert,
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
        ? NeoTheme.green.withValues(alpha: 0.35)
        : NeoTheme.red.withValues(alpha: 0.45);
    final bg = ok ? NeoTheme.mainPanelFill : const Color(0xFF1F1518);
    final fg = ok
        ? NeoTheme.green
        : NeoTheme.red.withValues(alpha: 0.95);
    final label = ok ? 'CONNECTED' : 'NO RPC';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: !ok && onOpenExpert != null
            ? () => onOpenExpert!()
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
      color: NeoTheme.mainPanelFill,
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

class _SettingsDrawer extends StatelessWidget {
  final ThemeData theme;
  final void Function(String key) onTap;

  const _SettingsDrawer({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final drawerWidth = min(360.0, MediaQuery.sizeOf(context).width * 0.85);
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
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manage your preferences, wallet, network, and data.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _SettingsDrawerItem(
              icon: Icons.tune_rounded,
              title: 'Preferences',
              subtitle: 'Prompt · Tuning · Security',
              onTap: () => onTap('sessions'),
            ),
            _SettingsDrawerItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              subtitle: 'Keys · Sessions · Staked MOR',
              onTap: () => onTap('wallet'),
            ),
            _SettingsDrawerItem(
              icon: PlatformCaps.isMobile ? Icons.link_rounded : Icons.terminal,
              title: PlatformCaps.isMobile ? 'Network' : 'Expert Mode',
              subtitle: PlatformCaps.isMobile
                  ? 'Blockchain RPC'
                  : 'Network · API · Gateway',
              onTap: () => onTap('expert'),
            ),
            _SettingsDrawerItem(
              icon: Icons.backup_outlined,
              title: 'Backup & Reset',
              subtitle: 'Backup · Restore · Reset',
              onTap: () => onTap('backup'),
            ),
            _SettingsDrawerItem(
              icon: Icons.info_outline,
              title: 'Version & Logs',
              subtitle: 'About · Log viewer',
              onTap: () => onTap('about'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsDrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
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
            Icon(Icons.chevron_right, size: 20, color: theme.hintColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final ModelStatusEntry entry;
  final VoidCallback onTap;

  const _ModelTile({required this.entry, required this.onTap});

  static Color _healthColor(double? pct) {
    if (pct == null) return NeoTheme.mainPanelOutline();
    if (pct >= 99.0) return NeoTheme.green;
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
      color: NeoTheme.mainPanelFill,
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
                      ? NeoTheme.green.withValues(alpha: 0.18)
                      : NeoTheme.mainPanelFill,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isTEE
                        ? NeoTheme.green.withValues(alpha: 0.35)
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
                                      ? NeoTheme.green.withValues(alpha: 0.7)
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

