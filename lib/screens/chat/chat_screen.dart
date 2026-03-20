import 'dart:math';

import 'package:flutter/material.dart';
import '../../services/bridge.dart';
import '../../services/chat_streaming_preference_store.dart';
import '../../services/session_duration_store.dart';
import '../../theme.dart';
import '../../utils/session_cost_estimate.dart';
import '../../utils/session_open_errors.dart';
import '../../utils/token_amount.dart';

class ChatScreen extends StatefulWidget {
  final String modelId;
  final String modelName;
  final bool isTEE;

  /// When set, load existing SQLite messages. If [resumeSessionId] is also set, use that
  /// on-chain session immediately. If [resumeSessionId] is null/empty, stay ready without
  /// a session until the first send (opens a new session, keeps full local context).
  final String? resumeConversationId;
  final String? resumeSessionId;

  const ChatScreen({
    super.key,
    required this.modelId,
    required this.modelName,
    required this.isTEE,
    this.resumeConversationId,
    this.resumeSessionId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  _BootstrapPhase _phase = _BootstrapPhase.bootstrapping;
  String? _error;
  String? _conversationId;
  String? _sessionId;
  final List<_ChatBubble> _messages = [];
  bool _sending = false;

  /// Persisted: request SSE/streaming from the provider vs one-shot completion.
  bool _preferStreaming = ChatStreamingPreferenceStore.defaultStreaming;

  /// On-chain session length for this chat (from [SessionDurationStore] presets).
  int _sessionDurationSeconds = SessionDurationStore.defaultSeconds;

  /// On-chain stake vs wallet (optional; from [SessionCostEstimate.loadStakePanel]).
  SessionStakePanel? _stakePanel;

  /// On error screen: persist chosen duration when retrying.
  bool _saveDurationAsDefaultOnRetry = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final sec = await SessionDurationStore.instance.readSeconds();
    if (!mounted) return;
    setState(() => _sessionDurationSeconds = sec);
    await _loadStreamingPreference();
    if (!mounted) return;
    await _bootstrap();
  }

  Future<void> _refreshCostHint() async {
    final panel = await SessionCostEstimate.loadStakePanel(
      widget.modelId,
      _sessionDurationSeconds,
      GoBridge(),
    );
    if (mounted) setState(() => _stakePanel = panel);
  }

  Future<void> _loadStreamingPreference() async {
    final v = await ChatStreamingPreferenceStore.instance.readPreferStreaming();
    if (mounted) setState(() => _preferStreaming = v);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _newConversationId() {
    final r = Random();
    return 'c-${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(0x7fffffff)}';
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = _BootstrapPhase.bootstrapping;
      _error = null;
    });
    final resumeCid = widget.resumeConversationId;
    final resumeSid = widget.resumeSessionId;
    if (resumeCid != null && resumeCid.isNotEmpty) {
      try {
        final bridge = GoBridge();
        final raw = bridge.getMessages(resumeCid);
        final loaded = <_ChatBubble>[];
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final role = m['role'] as String? ?? 'user';
          final content = m['content'] as String? ?? '';
          loaded.add(_ChatBubble(role: role, text: content));
        }
        if (!mounted) return;
        final sid = (resumeSid != null && resumeSid.isNotEmpty) ? resumeSid : null;
        setState(() {
          _conversationId = resumeCid;
          _sessionId = sid;
          _messages
            ..clear()
            ..addAll(loaded);
          _phase = _BootstrapPhase.ready;
        });
        _scrollToBottom();
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _phase = _BootstrapPhase.error;
          });
        }
        return;
      }
    }

    try {
      final bridge = GoBridge();
      await _refreshCostHint();
      final draft = bridge.claimEmptyDraftForModel(
        modelId: widget.modelId,
        modelName: widget.modelName,
        provider: '',
        isTEE: widget.isTEE,
      );
      var convId = draft['conversation_id'] as String? ?? '';
      var sid = draft['session_id'] as String? ?? '';

      if (convId.isNotEmpty) {
        if (sid.isEmpty) {
          final reuse = bridge.reusableSessionForModel(widget.modelId);
          var newSid = (reuse['session_id'] as String?)?.trim() ?? '';
          if (newSid.isEmpty) {
            final sess = bridge.openSession(widget.modelId, _sessionDurationSeconds, directPayment: false);
            final opened = sess['session_id'] as String?;
            if (opened == null || opened.isEmpty) {
              throw GoBridgeException('open session: missing session_id in response');
            }
            newSid = opened;
          }
          bridge.setConversationSession(conversationId: convId, sessionId: newSid);
          sid = newSid;
        }
        if (!mounted) return;
        setState(() {
          _conversationId = convId;
          _sessionId = sid;
          _phase = _BootstrapPhase.ready;
        });
        return;
      }

      convId = _newConversationId();
      bridge.createConversation(
        conversationId: convId,
        modelId: widget.modelId,
        modelName: widget.modelName,
        provider: '',
        isTEE: widget.isTEE,
      );
      final reuse = bridge.reusableSessionForModel(widget.modelId);
      var opened = (reuse['session_id'] as String?)?.trim() ?? '';
      if (opened.isEmpty) {
        final sess = bridge.openSession(widget.modelId, _sessionDurationSeconds, directPayment: false);
        final sid = sess['session_id'] as String?;
        if (sid == null || sid.isEmpty) {
          throw GoBridgeException('open session: missing session_id in response');
        }
        opened = sid;
      }
      bridge.setConversationSession(conversationId: convId, sessionId: opened);
      if (!mounted) return;
      setState(() {
        _conversationId = convId;
        _sessionId = opened;
        _phase = _BootstrapPhase.ready;
      });
    } on GoBridgeException catch (e) {
      if (mounted) {
        await _refreshCostHint();
        setState(() {
          _error = e.message;
          _phase = _BootstrapPhase.error;
        });
      }
    } catch (e) {
      if (mounted) {
        await _refreshCostHint();
        setState(() {
          _error = e.toString();
          _phase = _BootstrapPhase.error;
        });
      }
    }
  }

  Future<void> _retryBootstrap() async {
    if (_saveDurationAsDefaultOnRetry) {
      await SessionDurationStore.instance.writeSeconds(_sessionDurationSeconds);
    }
    await _bootstrap();
  }

  /// Opens an on-chain session for the current conversation and persists session_id in SQLite.
  Future<String?> _openSessionAndPersist() async {
    final cid = _conversationId;
    if (cid == null) return null;
    await _refreshCostHint();
    final bridge = GoBridge();
    final reuse = bridge.reusableSessionForModel(widget.modelId);
    var sid = (reuse['session_id'] as String?)?.trim() ?? '';
    if (sid.isEmpty) {
      final sess = bridge.openSession(widget.modelId, _sessionDurationSeconds, directPayment: false);
      final opened = sess['session_id'] as String?;
      if (opened == null || opened.isEmpty) {
        throw GoBridgeException('open session: missing session_id in response');
      }
      sid = opened;
    }
    bridge.setConversationSession(conversationId: cid, sessionId: sid);
    if (mounted) setState(() => _sessionId = sid);
    return sid;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final cid = _conversationId;
    if (text.isEmpty || cid == null || _sending) return;

    setState(() {
      _messages.add(_ChatBubble(role: 'user', text: text));
      _input.clear();
      _sending = true;
    });
    _scrollToBottom();

    var sid = _sessionId;
    if (sid == null || sid.isEmpty) {
      try {
        sid = await _openSessionAndPersist();
      } on GoBridgeException catch (e) {
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'user' && _messages.last.text == text) {
            _messages.removeLast();
          }
          _input.text = text;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionOpenErrorSnackMessage(e.message)),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                _input.text = text;
                _send();
              },
            ),
          ),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'user' && _messages.last.text == text) {
            _messages.removeLast();
          }
          _input.text = text;
          _sending = false;
        });
        return;
      }
    }

    if (sid == null || sid.isEmpty) {
      if (mounted) setState(() => _sending = false);
      return;
    }

    var streamingAssistantPending = false;
    try {
      final bridge = GoBridge();
      if (_preferStreaming) {
        var accumulated = '';
        if (mounted) {
          setState(() {
            _messages.add(_ChatBubble(role: 'assistant', text: ''));
          });
          streamingAssistantPending = true;
        }
        final res = bridge.sendPromptWithStream(
          sid,
          cid,
          text,
          stream: true,
          onDelta: (delta, isLast) {
            accumulated += delta;
            if (!mounted) return;
            setState(() {
              if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
                _messages.removeLast();
              }
              _messages.add(_ChatBubble(role: 'assistant', text: accumulated));
            });
            if (isLast) {
              _scrollToBottom();
            }
          },
        );
        final reply = res['response'] as String? ?? accumulated;
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
            _messages.removeLast();
          }
          _messages.add(
            _ChatBubble(
              role: 'assistant',
              text: reply.isEmpty ? '(empty response)' : reply,
            ),
          );
          _sending = false;
        });
      } else {
        final res = bridge.sendPrompt(sid, cid, text, stream: false);
        final reply = res['response'] as String? ?? '';
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatBubble(role: 'assistant', text: reply.isEmpty ? '(empty response)' : reply));
          _sending = false;
        });
      }
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        if (streamingAssistantPending &&
            _messages.isNotEmpty &&
            _messages.last.role == 'assistant') {
          _messages.removeLast();
        }
        _messages.add(
          _ChatBubble(
            role: 'assistant',
            text: 'Error: ${e.message}\n\nIf the on-chain session expired, tap Reconnect session below.',
            isError: true,
            onReconnect: _recoverSession,
          ),
        );
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (streamingAssistantPending &&
            _messages.isNotEmpty &&
            _messages.last.role == 'assistant') {
          _messages.removeLast();
        }
        _messages.add(_ChatBubble(role: 'assistant', text: 'Error: $e', isError: true));
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _recoverSession() async {
    final cid = _conversationId;
    if (cid == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await _openSessionAndPersist();
      if (!mounted) return;
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New session opened — send your message again.')),
        );
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sessionOpenErrorSnackMessage(e.message))),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.modelName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (widget.isTEE)
              Text(
                '🛡️ SECURE session',
                style: TextStyle(fontSize: 11, color: RedPillTheme.green.withValues(alpha: 0.85)),
              ),
          ],
        ),
      ),
      body: switch (_phase) {
        _BootstrapPhase.bootstrapping => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: RedPillTheme.green),
                const SizedBox(height: 20),
                Text(
                  'Opening on-chain session (${SessionDurationStore.formatDurationLabel(_sessionDurationSeconds)})…',
                  style: const TextStyle(color: Color(0xFF9CA3AF)),
                  textAlign: TextAlign.center,
                ),
                if (_stakePanel != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _StakePanelBody(panel: _stakePanel!, headlineGreen: false),
                  ),
                ],
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'This can take a minute (MOR stake / gas). Keep the app open.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        _BootstrapPhase.error => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 40), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Could not open session',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (_stakePanel != null) ...[
                    const SizedBox(height: 10),
                    _StakePanelBody(panel: _stakePanel!, headlineGreen: true),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _SessionOpenErrorCopy(theme: theme, rawError: _error),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Session length (next retry)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _sessionDurationSeconds,
                        items: [
                          for (final (label, sec) in SessionDurationStore.presets)
                            DropdownMenuItem<int>(value: sec, child: Text(label)),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _sessionDurationSeconds = v);
                          await _refreshCostHint();
                        },
                      ),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save as default for new chats', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Also stored under Network → Chat session length', style: TextStyle(fontSize: 11)),
                    value: _saveDurationAsDefaultOnRetry,
                    onChanged: (v) => setState(() => _saveDurationAsDefaultOnRetry = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => _retryBootstrap(),
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        _BootstrapPhase.ready => Column(
            children: [
              if (_sessionId == null || _sessionId!.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Material(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: RedPillTheme.green.withValues(alpha: 0.85)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No active on-chain session for this thread. A new one starts automatically when you send — your saved messages are still included as context.',
                              style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_sending && i == _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: RedPillTheme.green),
                            ),
                            SizedBox(width: 12),
                            Text('Thinking…', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                          ],
                        ),
                      );
                    }
                    final b = _messages[i];
                    final isUser = b.role == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
                        decoration: BoxDecoration(
                          color: isUser
                              ? RedPillTheme.green.withValues(alpha: 0.18)
                              : (b.isError ? const Color(0xFF450A0A) : RedPillTheme.surface),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isUser
                                ? RedPillTheme.green.withValues(alpha: 0.35)
                                : const Color(0xFF374151),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              b.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: b.isError ? const Color(0xFFFECACA) : null,
                                height: 1.35,
                              ),
                            ),
                            if (b.isError && b.onReconnect != null) ...[
                              const SizedBox(height: 10),
                              FilledButton.tonal(
                                onPressed: _sending ? null : b.onReconnect,
                                child: const Text('Reconnect session'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: RedPillTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          dense: true,
                          title: const Text(
                            'Streaming reply',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _preferStreaming
                                ? 'Provider sends tokens as they are generated (recommended).'
                                : 'Provider returns one complete message (can reduce overhead).',
                            style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.25),
                          ),
                          value: _preferStreaming,
                          activeThumbColor: RedPillTheme.green,
                          onChanged: _sending
                              ? null
                              : (v) {
                                  setState(() => _preferStreaming = v);
                                  ChatStreamingPreferenceStore.instance.writePreferStreaming(v);
                                },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'Message…',
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sending ? null : _send,
                            style: IconButton.styleFrom(
                              backgroundColor: RedPillTheme.green,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF374151),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 22),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }
}

/// Red “why it failed” + grey guidance; raw chain/proxy text tucked under expansion.
class _SessionOpenErrorCopy extends StatelessWidget {
  const _SessionOpenErrorCopy({required this.theme, required this.rawError});

  final ThemeData theme;
  final String? rawError;

  @override
  Widget build(BuildContext context) {
    final parts = explainSessionOpenError(rawError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Why it failed',
          style: TextStyle(
            color: theme.hintColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          parts.headline,
          style: const TextStyle(
            color: Color(0xFFF87171),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        if (parts.supporting != null && parts.supporting!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            parts.supporting!,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.4),
          ),
        ],
        if (parts.whatNext != null && parts.whatNext!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            parts.whatNext!,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
          ),
        ],
        if (parts.showTechnicalSection && parts.rawTechnical.isNotEmpty) ...[
          const SizedBox(height: 14),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              title: Text(
                'Technical details (optional)',
                style: TextStyle(color: theme.hintColor, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    parts.rawTechnical,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Stake headline + wallet + shortfall + footnotes for open-session UX.
class _StakePanelBody extends StatelessWidget {
  const _StakePanelBody({required this.panel, required this.headlineGreen});

  final SessionStakePanel panel;
  final bool headlineGreen;

  @override
  Widget build(BuildContext context) {
    final headlineStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: headlineGreen ? 13 : 12,
      height: 1.35,
      color: headlineGreen ? RedPillTheme.green.withValues(alpha: 0.9) : const Color(0xFF9CA3AF),
    );
    final bodyStyle = TextStyle(
      fontSize: headlineGreen ? 12 : 11,
      height: 1.4,
      color: headlineGreen ? const Color(0xFFCBD5E1) : const Color(0xFF6B7280),
    );
    final footStyle = TextStyle(
      fontSize: 10,
      height: 1.35,
      color: headlineGreen ? const Color(0xFF6B7280) : const Color(0xFF525252),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Estimated MOR moved for this open: ${panel.estimatedStakeMor} MOR',
          textAlign: TextAlign.center,
          style: headlineStyle,
        ),
        const SizedBox(height: 6),
        Text(
          'Your wallet MOR: ${panel.walletMor}',
          textAlign: TextAlign.center,
          style: bodyStyle,
        ),
        if (panel.hasShortfall) ...[
          const SizedBox(height: 6),
          Text(
            'Short by about ${formatWeiFixedDecimals(panel.shortfallWei.toString(), 2)} MOR for this estimate.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: headlineGreen ? 12 : 11,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: const Color(0xFFF59E0B),
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final f in panel.footnotes) ...[
          Text(f, textAlign: TextAlign.left, style: footStyle),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

enum _BootstrapPhase { bootstrapping, error, ready }

class _ChatBubble {
  final String role;
  final String text;
  final bool isError;
  final Future<void> Function()? onReconnect;

  _ChatBubble({required this.role, required this.text, this.isError = false, this.onReconnect});
}
