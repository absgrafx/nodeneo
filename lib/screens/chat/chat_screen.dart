import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bridge.dart';
import '../../widgets/chat_message_body.dart';
import '../../services/chat_streaming_preference_store.dart';
import '../../services/session_duration_store.dart';
import '../../theme.dart';
import '../../utils/session_cost_estimate.dart';
import '../../utils/session_open_errors.dart';
import '../../utils/token_amount.dart';

/// Top-level so [compute] can serialize it across isolate boundaries.
Map<String, dynamic> _openSessionInBackground(Map<String, dynamic> p) {
  return GoBridge().openSession(
    p['modelId'] as String,
    p['duration'] as int,
    directPayment: false,
  );
}

enum _LogLevel { working, info, warn, error, ok }

class _LogEntry {
  String message;
  _LogLevel level;
  _LogEntry(this.message, this.level);
}

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
  final _logScroll = ScrollController();

  _BootstrapPhase _phase = _BootstrapPhase.bootstrapping;
  String? _error;
  final List<_LogEntry> _bootLog = [];
  bool _showBootLog = true;
  String? _conversationId;
  String? _sessionId;
  final List<_ChatBubble> _messages = [];
  bool _sending = false;
  bool _reopeningSession = false;

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
    _logScroll.dispose();
    super.dispose();
  }

  void _addLog(String message, {_LogLevel level = _LogLevel.info}) {
    if (!mounted) return;
    setState(() => _bootLog.add(_LogEntry(message, level)));
    _scrollLogToBottom();
  }

  /// Start a step that will be marked complete later via [_completeStep].
  void _startStep(String message) {
    if (!mounted) return;
    setState(() => _bootLog.add(_LogEntry(message, _LogLevel.working)));
    _scrollLogToBottom();
  }

  /// Mark the last [_LogLevel.working] entry as done, optionally changing the message.
  void _completeStep({String? message, _LogLevel level = _LogLevel.ok}) {
    if (!mounted) return;
    setState(() {
      for (var i = _bootLog.length - 1; i >= 0; i--) {
        if (_bootLog[i].level == _LogLevel.working) {
          _bootLog[i].level = level;
          if (message != null) _bootLog[i].message = message;
          break;
        }
      }
    });
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _newConversationId() {
    final r = Random();
    return 'c-${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(0x7fffffff)}';
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = _BootstrapPhase.bootstrapping;
      _error = null;
      _bootLog.clear();
    });

    final resumeCid = widget.resumeConversationId;
    final resumeSid = widget.resumeSessionId;

    // --- Resume existing conversation (history tap) ---
    if (resumeCid != null && resumeCid.isNotEmpty) {
      _startStep('Resuming conversation…');
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
        _completeStep(message: 'Conversation loaded');
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
        _completeStep(message: 'Failed to load conversation', level: _LogLevel.error);
        if (mounted) {
          setState(() { _error = e.toString(); _phase = _BootstrapPhase.error; });
        }
        return;
      }
    }

    // --- New session flow ---
    try {
      final bridge = GoBridge();

      // 1. Connect to network (RPC / Diamond contract)
      _startStep('Connecting to Morpheus network…');
      await _refreshCostHint();
      _completeStep(message: 'Connected to network');

      // Internal: check if there's already a draft conversation with a live session
      final draft = bridge.claimEmptyDraftForModel(
        modelId: widget.modelId,
        modelName: widget.modelName,
        provider: '',
        isTEE: widget.isTEE,
      );
      var convId = draft['conversation_id'] as String? ?? '';
      var sid = draft['session_id'] as String? ?? '';

      // Fast path: draft already has a live session
      if (convId.isNotEmpty && sid.isNotEmpty) {
        _addLog('Existing session found — reusing', level: _LogLevel.ok);
        if (!mounted) return;
        await _transitionToReady(convId, sid);
        return;
      }

      // 2. Check for a reusable on-chain session for this model
      _startStep('Checking for reusable on-chain session…');
      final reuse = bridge.reusableSessionForModel(widget.modelId);
      var sessionId = (reuse['session_id'] as String?)?.trim() ?? '';

      if (sessionId.isNotEmpty) {
        _completeStep(message: 'Reusing existing session');
      } else {
        _completeStep(message: 'No reusable session');

        // 3. Open a new session (provider selection → TEE attestation → on-chain stake)
        await _openSessionWithLog(widget.modelId);
        if (_phase == _BootstrapPhase.error) return;
        sessionId = _lastOpenedSessionId!;
      }

      // 4. Create local conversation and link the session
      _startStep('Creating conversation…');
      if (convId.isEmpty) {
        convId = _newConversationId();
        bridge.createConversation(
          conversationId: convId,
          modelId: widget.modelId,
          modelName: widget.modelName,
          provider: '',
          isTEE: widget.isTEE,
        );
      }
      bridge.setConversationSession(conversationId: convId, sessionId: sessionId);
      _completeStep(message: 'Conversation created');

      // 5. Ready
      if (!mounted) return;
      await _transitionToReady(convId, sessionId);
    } on GoBridgeException catch (e) {
      if (_phase != _BootstrapPhase.error) {
        _completeStep(message: e.message, level: _LogLevel.error);
        if (mounted) {
          await _refreshCostHint();
          setState(() { _error = e.message; _phase = _BootstrapPhase.error; });
        }
      }
    } catch (e) {
      if (_phase != _BootstrapPhase.error) {
        _completeStep(message: e.toString(), level: _LogLevel.error);
        if (mounted) {
          await _refreshCostHint();
          setState(() { _error = e.toString(); _phase = _BootstrapPhase.error; });
        }
      }
    }
  }

  Future<void> _transitionToReady(String convId, String sessionId) async {
    _addLog(
      widget.isTEE
          ? 'Secure session established — you can begin'
          : 'Session established — you can begin',
      level: _LogLevel.ok,
    );
    // Let the user see the completed log for a moment
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _conversationId = convId;
      _sessionId = sessionId;
      _showBootLog = true;
      _phase = _BootstrapPhase.ready;
    });
  }

  String? _lastOpenedSessionId;

  /// Runs the real proxy-router OpenSession flow on a background isolate.
  /// Go internally: select provider → TEE attestation (if secure) → on-chain open.
  Future<void> _openSessionWithLog(String modelId) async {
    // The Go SDK's OpenSession does these steps internally in order:
    //   1. Select provider from bids
    //   2. If TEE: verify hardware attestation (TLS fingerprint, RTMR registers)
    //   3. Open on-chain session (MOR stake transaction)
    // We show the TEE step as the active spinner since it's the first meaningful wait.
    if (widget.isTEE) {
      _startStep('Verifying secure (TEE) attestation with provider…');
    } else {
      _startStep('Opening on-chain session (staking MOR)…');
    }

    // Let the UI render before the blocking compute call
    await Future<void>.delayed(Duration.zero);

    try {
      final result = await compute(_openSessionInBackground, {
        'modelId': modelId,
        'duration': _sessionDurationSeconds,
      }).timeout(
        const Duration(seconds: 120),
        onTimeout: () => <String, dynamic>{'error': 'Session open timed out after 120s'},
      );

      if (!mounted) return;

      if (result.containsKey('error')) {
        throw GoBridgeException(result['error'] as String);
      }

      final sid = result['session_id'] as String?;
      if (sid == null || sid.isEmpty) {
        throw GoBridgeException('open session: missing session_id in response');
      }

      if (widget.isTEE) {
        _completeStep(message: 'TEE attestation verified');
        _startStep('Opening on-chain session (staking MOR)…');
      }

      _completeStep(message: 'On-chain session opened (MOR staked)');
      _lastOpenedSessionId = sid;
    } on GoBridgeException catch (e) {
      _completeStep(message: e.message, level: _LogLevel.error);
      if (mounted) {
        await _refreshCostHint();
        setState(() { _error = e.message; _phase = _BootstrapPhase.error; });
      }
      rethrow;
    } catch (e) {
      _completeStep(message: e.toString(), level: _LogLevel.error);
      if (mounted) {
        await _refreshCostHint();
        setState(() { _error = e.toString(); _phase = _BootstrapPhase.error; });
      }
      rethrow;
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
      _showBootLog = false;
      _messages.add(_ChatBubble(role: 'user', text: text));
      _input.clear();
      _sending = true;
    });
    _scrollToBottom();

    var sid = _sessionId;
    if (sid == null || sid.isEmpty) {
      if (mounted) setState(() => _reopeningSession = true);
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
          _reopeningSession = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionOpenErrorSnackMessage(e.message)),
            duration: const Duration(seconds: 8),
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
          _reopeningSession = false;
        });
        return;
      }
      if (mounted) setState(() => _reopeningSession = false);
    }

    if (sid == null || sid.isEmpty) {
      if (mounted) setState(() { _sending = false; _reopeningSession = false; });
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
    setState(() {
      _sending = true;
      _reopeningSession = true;
      _sessionId = null;
    });
    try {
      await _openSessionAndPersist();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _reopeningSession = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New session opened — send your message again.')),
        );
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _reopeningSession = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionOpenErrorSnackMessage(e.message)),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _recoverSession,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _reopeningSession = false;
        });
      }
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isTEE) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: NeoTheme.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: NeoTheme.green.withValues(alpha: 0.35)),
                ),
                child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 14))),
              ),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.modelName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (widget.isTEE)
                  Text(
                    'Secure Session',
                    style: TextStyle(fontSize: 11, color: NeoTheme.green.withValues(alpha: 0.85)),
                  ),
              ],
            ),
          ],
        ),
      ),
      body: switch (_phase) {
        _BootstrapPhase.bootstrapping => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NeoTheme.green),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Setting up session (${SessionDurationStore.formatDurationLabel(_sessionDurationSeconds)})',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: _logScroll,
                    itemCount: _bootLog.length,
                    itemBuilder: (ctx, i) {
                      final e = _bootLog[i];
                      final Color color;
                      final Widget leading;
                      switch (e.level) {
                        case _LogLevel.working:
                          color = const Color(0xFF9CA3AF);
                          leading = const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF9CA3AF)),
                          );
                        case _LogLevel.info:
                          color = const Color(0xFF6B7280);
                          leading = Icon(Icons.chevron_right_rounded, size: 14, color: color);
                        case _LogLevel.warn:
                          color = const Color(0xFFF59E0B);
                          leading = Icon(Icons.warning_amber_rounded, size: 14, color: color);
                        case _LogLevel.error:
                          color = const Color(0xFFF87171);
                          leading = Icon(Icons.error_outline_rounded, size: 14, color: color);
                        case _LogLevel.ok:
                          color = NeoTheme.green;
                          leading = Icon(Icons.check_circle_outline_rounded, size: 14, color: color);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            leading,
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.message,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  height: 1.4,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This can take a minute (MOR stake + provider handshake). Keep the app open.',
                  style: TextStyle(color: Color(0xFF525252), fontSize: 11),
                ),
              ],
            ),
          ),
        _BootstrapPhase.error => isTeeAttestationFailure(_error)
            ? _TeeFailureScreen(rawError: _error, theme: theme)
            : SafeArea(
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
                        style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
        _BootstrapPhase.ready => Column(
            children: [
              if (_showBootLog && _messages.isEmpty && _bootLog.isNotEmpty)
                _BootLogBanner(entries: _bootLog, isTEE: widget.isTEE),
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
                          Icon(Icons.info_outline, size: 18, color: NeoTheme.green.withValues(alpha: 0.85)),
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: NeoTheme.green),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _reopeningSession
                                  ? 'Reopening session (staking MOR)…'
                                  : 'Thinking…',
                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                            ),
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
                              ? NeoTheme.green.withValues(alpha: 0.18)
                              : (b.isError ? const Color(0xFF450A0A) : NeoTheme.surface),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isUser
                                ? NeoTheme.green.withValues(alpha: 0.35)
                                : const Color(0xFF374151),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isUser)
                              Row(
                                children: [
                                  const Spacer(),
                                  IconButton(
                                    tooltip: b.isError ? 'Copy error text' : 'Copy response',
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    icon: Icon(
                                      Icons.copy_rounded,
                                      size: 18,
                                      color: theme.hintColor,
                                    ),
                                    onPressed: b.text.isEmpty
                                        ? null
                                        : () async {
                                            await Clipboard.setData(ClipboardData(text: b.text));
                                            if (!ctx.mounted) return;
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  b.isError ? 'Error text copied' : 'Response copied',
                                                ),
                                                behavior: SnackBarBehavior.floating,
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                  ),
                                ],
                              ),
                            buildChatMessageBody(
                              theme,
                              role: b.role,
                              text: b.text,
                              isError: b.isError,
                            ),
                            if (b.isError && b.onReconnect != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: _sending ? null : b.onReconnect,
                                    child: const Text('Reconnect session'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _messages.remove(b));
                                    },
                                    child: const Text('Dismiss'),
                                  ),
                                ],
                              ),
                            ],
                            if (b.isError && b.onReconnect == null) ...[
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () {
                                  setState(() => _messages.remove(b));
                                },
                                child: const Text('Dismiss'),
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
                              backgroundColor: NeoTheme.green,
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

/// Dedicated screen for TEE attestation failures — no MOR info, no retry,
/// just a clear warning and a back button.
class _TeeFailureScreen extends StatelessWidget {
  const _TeeFailureScreen({required this.rawError, required this.theme});

  final String? rawError;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final parts = explainSessionOpenError(rawError);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 1),
            // Red circle-slash shield icon
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35), width: 2),
                  ),
                  child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 30))),
                ),
                Positioned(
                  child: Icon(Icons.block_rounded, size: 72, color: const Color(0xFFEF4444).withValues(alpha: 0.55)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Secure (TEE) Verification Failed',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF87171),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This provider did not pass hardware attestation.\nPrompts are not permitted on unverified endpoints.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            if (parts.supporting != null && parts.supporting!.trim().isNotEmpty)
              Text(
                parts.supporting!,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.4),
              ),
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
            const Spacer(flex: 2),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Go Back', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
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
      color: headlineGreen ? NeoTheme.green.withValues(alpha: 0.9) : const Color(0xFF9CA3AF),
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

class _BootLogBanner extends StatelessWidget {
  final List<_LogEntry> entries;
  final bool isTEE;
  const _BootLogBanner({required this.entries, required this.isTEE});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: NeoTheme.mainPanelFill,
        border: Border(
          bottom: BorderSide(
            color: NeoTheme.green.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconForLevel(e.level),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.message,
                      style: TextStyle(
                        color: _colorForLevel(e.level),
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
      ),
    );
  }

  static Color _colorForLevel(_LogLevel l) => switch (l) {
        _LogLevel.working => const Color(0xFF9CA3AF),
        _LogLevel.info => const Color(0xFF6B7280),
        _LogLevel.warn => const Color(0xFFF59E0B),
        _LogLevel.error => const Color(0xFFF87171),
        _LogLevel.ok => NeoTheme.green,
      };

  static Widget _iconForLevel(_LogLevel l) => switch (l) {
        _LogLevel.working => const SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF9CA3AF)),
          ),
        _LogLevel.info => Icon(Icons.chevron_right_rounded, size: 12, color: _colorForLevel(l)),
        _LogLevel.warn => Icon(Icons.warning_amber_rounded, size: 12, color: _colorForLevel(l)),
        _LogLevel.error => Icon(Icons.error_outline_rounded, size: 12, color: _colorForLevel(l)),
        _LogLevel.ok => Icon(Icons.check_circle_outline_rounded, size: 12, color: _colorForLevel(l)),
      };
}

class _ChatBubble {
  final String role;
  final String text;
  final bool isError;
  final Future<void> Function()? onReconnect;

  _ChatBubble({required this.role, required this.text, this.isError = false, this.onReconnect});
}
