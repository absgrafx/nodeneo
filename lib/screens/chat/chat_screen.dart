import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bridge.dart';
import '../../widgets/chat_message_body.dart';
import '../../services/chat_streaming_preference_store.dart';
import '../../services/default_tuning_store.dart';
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

  // --- Tuning parameters (Expert Mode) ---
  double _temperature = 1.0;
  double _topP = 1.0;
  int _maxTokens = 2048;
  double _frequencyPenalty = 0.0;
  double _presencePenalty = 0.0;

  // --- System prompt ---
  String _systemPrompt = '';

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
    await _loadDefaultTuning();
    if (!mounted) return;
    await _bootstrap();
  }

  Future<void> _loadDefaultTuning() async {
    final d = await DefaultTuningStore.instance.read();
    if (!mounted) return;
    final sp = d['system_prompt'] as String? ?? DefaultTuningStore.defaultSystemPrompt;
    try { GoBridge().setPreference('_debug_sys_prompt_load', 'len=${sp.length}_empty=${sp.isEmpty}'); } catch (_) {}
    setState(() {
      _temperature = (d['temperature'] as num?)?.toDouble() ?? DefaultTuningStore.defaultTemperature;
      _topP = (d['top_p'] as num?)?.toDouble() ?? DefaultTuningStore.defaultTopP;
      _maxTokens = (d['max_tokens'] as num?)?.toInt() ?? DefaultTuningStore.defaultMaxTokens;
      _frequencyPenalty = (d['frequency_penalty'] as num?)?.toDouble() ?? DefaultTuningStore.defaultFrequencyPenalty;
      _presencePenalty = (d['presence_penalty'] as num?)?.toDouble() ?? DefaultTuningStore.defaultPresencePenalty;
      _systemPrompt = sp;
    });
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
          Map<String, dynamic>? meta;
          final rawMeta = m['metadata'] as String?;
          if (rawMeta != null && rawMeta.isNotEmpty) {
            try { meta = jsonDecode(rawMeta) as Map<String, dynamic>; } catch (_) {}
          }
          loaded.add(_ChatBubble(role: role, text: content, metadata: meta));
        }
        if (!mounted) return;
        _loadTuningForConversation(resumeCid);
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
      _startStep('Connecting to Morpheus network…');
      await _refreshCostHint();

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
        _completeStep(message: 'Existing session found');
        if (!mounted) return;
        _transitionToReady(convId, sid);
        return;
      }

      _completeStep(message: 'Connected to network');

      final reuse = bridge.reusableSessionForModel(widget.modelId);
      var sessionId = (reuse['session_id'] as String?)?.trim() ?? '';

      if (sessionId.isNotEmpty) {
        _addLog('Reusing existing on-chain session', level: _LogLevel.ok);
      } else {
        await _openSessionWithLog(widget.modelId);
        if (_phase == _BootstrapPhase.error) return;
        sessionId = _lastOpenedSessionId!;
      }

      // Create local conversation and link the session
      _startStep('Preparing conversation…');
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
      _completeStep(message: 'Conversation ready');

      // Ready
      if (!mounted) return;
      _transitionToReady(convId, sessionId);
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

  String? _readyBannerMessage;

  void _transitionToReady(String convId, String sessionId) {
    // Ensure the system prompt is written for every conversation path
    // (new, draft-with-session, draft-without-session).
    try { GoBridge().setPreference('_debug_sys_prompt_ready', 'len=${_systemPrompt.length}_empty=${_systemPrompt.isEmpty}_conv=$convId'); } catch (_) {}
    if (_systemPrompt.isNotEmpty) {
      try {
        GoBridge().setConversationSystemPrompt(conversationId: convId, prompt: _systemPrompt);
      } catch (e) {
        try { GoBridge().setPreference('_debug_sys_prompt_err', e.toString()); } catch (_) {}
      }
    }

    final readyMsg = widget.isTEE
        ? 'Secure session ready for ${widget.modelName}'
        : 'Session ready for ${widget.modelName}';
    if (!mounted) return;
    setState(() {
      _conversationId = convId;
      _sessionId = sessionId;
      _readyBannerMessage = readyMsg;
      _showBootLog = true;
      _phase = _BootstrapPhase.ready;
    });
  }

  String? _lastOpenedSessionId;

  /// Runs the real proxy-router OpenSession flow on a background isolate.
  /// Go internally: select provider → TEE attestation (if secure) → on-chain open.
  Future<void> _openSessionWithLog(String modelId) async {
    if (widget.isTEE) {
      _startStep('Verifying secure (TEE) attestation…');
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

      _completeStep(message: 'On-chain session opened');
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

  Map<String, dynamic>? _extractMetadata(Map<String, dynamic> res) {
    final meta = <String, dynamic>{};
    if (res.containsKey('latency_ms')) meta['latency_ms'] = res['latency_ms'];
    if (res.containsKey('provider_response')) meta['provider_response'] = res['provider_response'];
    // Legacy fields (pre-existing metadata stored in DB before the provider_response change)
    if (res.containsKey('finish_reason')) meta['finish_reason'] = res['finish_reason'];
    if (res.containsKey('usage')) meta['usage'] = res['usage'];
    if (res.containsKey('model')) meta['model'] = res['model'];
    return meta.isEmpty ? null : meta;
  }

  void _loadTuningForConversation(String conversationId) {
    try {
      final raw = GoBridge().getConversationTuning(conversationId);
      if (raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _temperature = (json['temperature'] as num?)?.toDouble() ?? 1.0;
          _topP = (json['top_p'] as num?)?.toDouble() ?? 1.0;
          _maxTokens = (json['max_tokens'] as num?)?.toInt() ?? 2048;
          _frequencyPenalty = (json['frequency_penalty'] as num?)?.toDouble() ?? 0.0;
          _presencePenalty = (json['presence_penalty'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {}
    try {
      final sp = GoBridge().getConversationSystemPrompt(conversationId);
      if (sp.isNotEmpty) setState(() => _systemPrompt = sp);
    } catch (_) {}
  }

  void _saveTuningForConversation() {
    final cid = _conversationId;
    if (cid == null) return;
    try {
      final json = jsonEncode({
        'temperature': _temperature,
        'top_p': _topP,
        'max_tokens': _maxTokens,
        'frequency_penalty': _frequencyPenalty,
        'presence_penalty': _presencePenalty,
      });
      GoBridge().setConversationTuning(conversationId: cid, tuningJSON: json);
    } catch (_) {}
  }

  void _saveSystemPromptForConversation() {
    final cid = _conversationId;
    if (cid == null) return;
    try {
      GoBridge().setConversationSystemPrompt(conversationId: cid, prompt: _systemPrompt);
    } catch (_) {}
  }

  bool get _hasTuningOverrides =>
      _temperature != 1.0 ||
      _topP != 1.0 ||
      _maxTokens != 2048 ||
      _frequencyPenalty != 0.0 ||
      _presencePenalty != 0.0 ||
      !_preferStreaming ||
      _systemPrompt.isNotEmpty;

  Map<String, dynamic> _buildTuningOptions() {
    final opts = <String, dynamic>{};
    if (_temperature != 1.0) opts['temperature'] = _temperature;
    if (_topP != 1.0) opts['top_p'] = _topP;
    if (_maxTokens != 2048) opts['max_tokens'] = _maxTokens;
    if (_frequencyPenalty != 0.0) opts['frequency_penalty'] = _frequencyPenalty;
    if (_presencePenalty != 0.0) opts['presence_penalty'] = _presencePenalty;
    return opts;
  }

  void _stopGeneration() {
    GoBridge().cancelPrompt();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final cid = _conversationId;
    if (text.isEmpty || cid == null || _sending) return;

    setState(() {
      _showBootLog = false;
      _readyBannerMessage = null;
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
        var thinkingAccumulated = '';
        var thinkingStartTime = DateTime.now();
        int streamBubbleIdx = -1;
        if (mounted) {
          setState(() {
            _messages.add(_ChatBubble(role: 'assistant', text: ''));
            streamBubbleIdx = _messages.length - 1;
          });
          streamingAssistantPending = true;
        }
        var lastUiUpdate = DateTime.now();
        const uiThrottle = Duration(milliseconds: 33);
        final res = await bridge.sendPromptWithOptionsAsync(
          sid,
          cid,
          text,
          stream: true,
          options: _buildTuningOptions(),
          onDelta: (delta, isThinking, isLast) {
            if (isThinking) {
              if (thinkingAccumulated.isEmpty) {
                thinkingStartTime = DateTime.now();
              }
              thinkingAccumulated += delta;
            } else {
              accumulated += delta;
            }
            if (!mounted || streamBubbleIdx < 0) return;
            final now = DateTime.now();
            if (isLast || now.difference(lastUiUpdate) >= uiThrottle) {
              lastUiUpdate = now;
              setState(() {
                _messages[streamBubbleIdx] = _ChatBubble(
                  role: 'assistant',
                  text: accumulated,
                  thinkingText: thinkingAccumulated.isNotEmpty ? thinkingAccumulated : null,
                  thinkingDuration: thinkingAccumulated.isNotEmpty
                      ? DateTime.now().difference(thinkingStartTime)
                      : null,
                  isThinkingLive: isThinking && !isLast,
                );
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
          },
        );
        final reply = res['response'] as String? ?? accumulated;
        final wasCancelled = res['cancelled'] == true;
        final meta = _extractMetadata(res);
        if (!mounted) return;
        setState(() {
          if (streamBubbleIdx >= 0 && streamBubbleIdx < _messages.length) {
            if (reply.isEmpty && !wasCancelled) {
              _messages[streamBubbleIdx] = _ChatBubble(
                role: 'assistant',
                text: 'No response received — the provider may be busy.',
                isError: true,
                onRetry: () async {
                  _input.text = text;
                  _send();
                },
              );
            } else {
              _messages[streamBubbleIdx] = _ChatBubble(
                role: 'assistant',
                text: reply,
                metadata: meta,
                isStopped: wasCancelled,
                thinkingText: thinkingAccumulated.isNotEmpty ? thinkingAccumulated : null,
                thinkingDuration: thinkingAccumulated.isNotEmpty
                    ? DateTime.now().difference(thinkingStartTime)
                    : null,
              );
            }
          }
          _sending = false;
        });
      } else {
        final res = await bridge.sendPromptWithOptionsAsync(
          sid,
          cid,
          text,
          stream: false,
          options: _buildTuningOptions(),
          onDelta: (_, __, ___) {},
        );
        final reply = res['response'] as String? ?? '';
        final meta = _extractMetadata(res);
        if (!mounted) return;
        setState(() {
          if (reply.isEmpty) {
            _messages.add(_ChatBubble(
              role: 'assistant',
              text: 'No response received — the provider may be busy.',
              isError: true,
              onRetry: () async {
                _input.text = text;
                _send();
              },
            ));
          } else {
            _messages.add(_ChatBubble(role: 'assistant', text: reply, metadata: meta));
          }
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

  void _showTuningDrawer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NeoTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final spController = TextEditingController(text: _systemPrompt);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4B5563),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Chat Tuning',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('System Prompt', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Defines the assistant\'s persona for this chat.\n'
                            'Start with "You are..." to set the role.\n'
                            'Example: "You are a concise Solidity auditor."',
                        preferBelow: false,
                        triggerMode: TooltipTriggerMode.tap,
                        showDuration: const Duration(seconds: 5),
                        child: Icon(Icons.info_outline, size: 14, color: const Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: spController,
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'e.g. "You are a concise technical assistant."',
                      hintStyle: TextStyle(fontSize: 11, color: const Color(0xFF6B7280).withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF374151)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF374151)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: NeoTheme.green.withValues(alpha: 0.6)),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    onChanged: (v) {
                      setState(() => _systemPrompt = v.trim());
                      _saveSystemPromptForConversation();
                    },
                  ),
                  const Divider(height: 24, color: Color(0xFF374151)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Streaming', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'When on, tokens appear as they are generated.\nWhen off, the full response is delivered at once.',
                          preferBelow: false,
                          triggerMode: TooltipTriggerMode.tap,
                          showDuration: const Duration(seconds: 4),
                          child: Icon(Icons.info_outline, size: 14, color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      _preferStreaming ? 'Tokens arrive in real-time' : 'Full response delivered at once',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                    value: _preferStreaming,
                    activeColor: NeoTheme.green,
                    onChanged: (v) {
                      setState(() => _preferStreaming = v);
                      setSheetState(() {});
                      ChatStreamingPreferenceStore.instance.writePreferStreaming(v);
                    },
                  ),
                  const Divider(height: 24, color: Color(0xFF374151)),
                  _TuningSlider(
                    label: 'Temperature',
                    tooltip: 'Controls randomness. Lower values make output\nmore focused; higher values more creative.',
                    value: _temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    format: (v) => v.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _temperature = v);
                      setSheetState(() {});
                      _saveTuningForConversation();
                    },
                  ),
                  const SizedBox(height: 8),
                  _TuningSlider(
                    label: 'Top P',
                    tooltip: 'Nucleus sampling. Limits token choices to the\ntop P probability mass. Lower = more predictable.',
                    value: _topP,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    format: (v) => v.toStringAsFixed(2),
                    onChanged: (v) {
                      setState(() => _topP = v);
                      setSheetState(() {});
                      _saveTuningForConversation();
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Max Tokens', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: 'Maximum number of tokens in the response.\nHigher values allow longer replies.',
                              preferBelow: false,
                              triggerMode: TooltipTriggerMode.tap,
                              showDuration: const Duration(seconds: 4),
                              child: Icon(Icons.info_outline, size: 14, color: const Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: _maxTokens > 64
                            ? () {
                                final next = (_maxTokens - 256).clamp(64, 16384);
                                setState(() => _maxTokens = next);
                                setSheetState(() {});
                                _saveTuningForConversation();
                              }
                            : null,
                      ),
                      Text(
                        '$_maxTokens',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: _maxTokens < 16384
                            ? () {
                                final next = (_maxTokens + 256).clamp(64, 16384);
                                setState(() => _maxTokens = next);
                                setSheetState(() {});
                                _saveTuningForConversation();
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TuningSlider(
                    label: 'Frequency Penalty',
                    tooltip: 'Penalises tokens based on how often they already\nappeared. Reduces repetitive phrasing.',
                    value: _frequencyPenalty,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    format: (v) => v.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _frequencyPenalty = v);
                      setSheetState(() {});
                      _saveTuningForConversation();
                    },
                  ),
                  const SizedBox(height: 8),
                  _TuningSlider(
                    label: 'Presence Penalty',
                    tooltip: 'Penalises tokens that have appeared at all.\nEncourages the model to explore new topics.',
                    value: _presencePenalty,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    format: (v) => v.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _presencePenalty = v);
                      setSheetState(() {});
                      _saveTuningForConversation();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await DefaultTuningStore.instance.write(
                              temperature: _temperature,
                              topP: _topP,
                              maxTokens: _maxTokens,
                              frequencyPenalty: _frequencyPenalty,
                              presencePenalty: _presencePenalty,
                              systemPrompt: _systemPrompt,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Current settings saved as default for new chats'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Save as default'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NeoTheme.green,
                            side: BorderSide(color: NeoTheme.green.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _preferStreaming = ChatStreamingPreferenceStore.defaultStreaming;
                              _temperature = DefaultTuningStore.defaultTemperature;
                              _topP = DefaultTuningStore.defaultTopP;
                              _maxTokens = DefaultTuningStore.defaultMaxTokens;
                              _frequencyPenalty = DefaultTuningStore.defaultFrequencyPenalty;
                              _presencePenalty = DefaultTuningStore.defaultPresencePenalty;
                              _systemPrompt = DefaultTuningStore.defaultSystemPrompt;
                            });
                            spController.text = _systemPrompt;
                            setSheetState(() {});
                            ChatStreamingPreferenceStore.instance.writePreferStreaming(
                              ChatStreamingPreferenceStore.defaultStreaming,
                            );
                            _saveTuningForConversation();
                            _saveSystemPromptForConversation();
                          },
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('Reset to defaults'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMetadataSheet(BuildContext ctx, Map<String, dynamic> metadata) {
    final encoder = const JsonEncoder.withIndent('  ');
    final formatted = encoder.convert(metadata);
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: NeoTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B5563),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Response Info',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 18, color: Theme.of(sheetCtx).hintColor),
                    tooltip: 'Copy JSON',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: formatted));
                      if (!sheetCtx.mounted) return;
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(
                        const SnackBar(
                          content: Text('Metadata copied'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (metadata['latency_ms'] != null)
                _MetadataRow(label: 'Latency', value: '${metadata['latency_ms']} ms'),
              ..._buildProviderSummaryRows(metadata),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: SelectableText(
                    formatted,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF94A3B8),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildProviderSummaryRows(Map<String, dynamic> metadata) {
    final rows = <Widget>[];
    final pr = metadata['provider_response'];
    if (pr is Map<String, dynamic>) {
      // Usage block (works for both streaming and non-streaming shapes)
      final usage = pr['usage'];
      if (usage is Map) {
        if (usage['prompt_tokens'] != null)
          rows.add(_MetadataRow(label: 'Prompt tokens', value: '${usage['prompt_tokens']}'));
        if (usage['completion_tokens'] != null)
          rows.add(_MetadataRow(label: 'Completion tokens', value: '${usage['completion_tokens']}'));
        if (usage['total_tokens'] != null)
          rows.add(_MetadataRow(label: 'Total tokens', value: '${usage['total_tokens']}'));
      }
      // Finish reason from choices
      final choices = pr['choices'];
      if (choices is List && choices.isNotEmpty) {
        final firstChoice = choices[0];
        if (firstChoice is Map) {
          final fr = firstChoice['finish_reason'] ?? firstChoice['finishReason'];
          if (fr != null) rows.add(_MetadataRow(label: 'Finish reason', value: '$fr'));
        }
      }
      // Model (if present)
      if (pr['model'] != null) {
        rows.add(_MetadataRow(label: 'Model', value: '${pr['model']}'));
      }
      // Created timestamp
      if (pr['created'] != null) {
        rows.add(_MetadataRow(label: 'Created', value: '${pr['created']}'));
      }
      // System fingerprint
      if (pr['system_fingerprint'] != null) {
        rows.add(_MetadataRow(label: 'System fingerprint', value: '${pr['system_fingerprint']}'));
      }
    } else {
      // Legacy metadata from older DB entries
      if (metadata['finish_reason'] != null)
        rows.add(_MetadataRow(label: 'Finish reason', value: '${metadata['finish_reason']}'));
      final usage = metadata['usage'];
      if (usage is Map) {
        if (usage['prompt_tokens'] != null)
          rows.add(_MetadataRow(label: 'Prompt tokens', value: '${usage['prompt_tokens']}'));
        if (usage['completion_tokens'] != null)
          rows.add(_MetadataRow(label: 'Completion tokens', value: '${usage['completion_tokens']}'));
        if (usage['total_tokens'] != null)
          rows.add(_MetadataRow(label: 'Total tokens', value: '${usage['total_tokens']}'));
      }
      if (metadata['model'] != null)
        rows.add(_MetadataRow(label: 'Model', value: '${metadata['model']}'));
    }
    return rows;
  }

  Widget _buildSingleStatusLine() {
    final entry = _bootLog.isNotEmpty ? _bootLog.last : null;
    final message = entry?.message ?? 'Preparing…';
    final level = entry?.level ?? _LogLevel.working;

    final Color color;
    final Widget leading;
    switch (level) {
      case _LogLevel.working:
        color = const Color(0xFF9CA3AF);
        leading = const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: NeoTheme.green),
        );
      case _LogLevel.ok:
        color = NeoTheme.green;
        leading = Icon(Icons.check_circle_outline_rounded, size: 18, color: color);
      case _LogLevel.error:
        color = const Color(0xFFF87171);
        leading = Icon(Icons.error_outline_rounded, size: 18, color: color);
      case _LogLevel.warn:
        color = const Color(0xFFF59E0B);
        leading = Icon(Icons.warning_amber_rounded, size: 18, color: color);
      case _LogLevel.info:
        color = const Color(0xFF6B7280);
        leading = Icon(Icons.chevron_right_rounded, size: 18, color: color);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ),
      ],
    );
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
        _BootstrapPhase.bootstrapping => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _buildSingleStatusLine(),
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
              if (_readyBannerMessage != null && _messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: NeoTheme.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isTEE ? Icons.verified_user_rounded : Icons.check_circle_rounded,
                            size: 22,
                            color: NeoTheme.green,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              _readyBannerMessage!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: NeoTheme.green,
                              ),
                            ),
                          ),
                          if (widget.isTEE) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.verified_user_rounded,
                              size: 22,
                              color: NeoTheme.green,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
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
                                  if (b.metadata != null && b.metadata!.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Response info',
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      icon: Icon(
                                        Icons.data_object_rounded,
                                        size: 18,
                                        color: theme.hintColor,
                                      ),
                                      onPressed: () => _showMetadataSheet(ctx, b.metadata!),
                                    ),
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
                            if (b.thinkingText != null && b.thinkingText!.isNotEmpty)
                              _ThinkingZone(
                                text: b.thinkingText!,
                                duration: b.thinkingDuration,
                                isLive: b.isThinkingLive,
                              ),
                            buildChatMessageBody(
                              theme,
                              role: b.role,
                              text: b.text,
                              isError: b.isError,
                            ),
                            if (b.isStopped)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '⏹ Generation stopped',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: NeoTheme.amber.withValues(alpha: 0.7),
                                  ),
                                ),
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
                            if (b.isError && b.onRetry != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: _sending
                                        ? null
                                        : () {
                                            setState(() => _messages.remove(b));
                                            b.onRetry!();
                                          },
                                    child: const Text('Tap to retry'),
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
                            if (b.isError && b.onReconnect == null && b.onRetry == null) ...[
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
                          IconButton(
                            onPressed: _sending ? null : _showTuningDrawer,
                            tooltip: 'Chat tuning',
                            icon: Icon(
                              Icons.tune_rounded,
                              size: 22,
                              color: _hasTuningOverrides
                                  ? NeoTheme.green
                                  : Theme.of(context).hintColor,
                            ),
                          ),
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
                          _sending
                              ? IconButton.filled(
                                  onPressed: _stopGeneration,
                                  style: IconButton.styleFrom(
                                    backgroundColor: NeoTheme.amber,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.stop_rounded, size: 22),
                                )
                              : IconButton.filled(
                                  onPressed: _send,
                                  style: IconButton.styleFrom(
                                    backgroundColor: NeoTheme.green,
                                    foregroundColor: Colors.white,
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
  final bool isStopped;
  final String? thinkingText;
  final Duration? thinkingDuration;
  final bool isThinkingLive;
  final Future<void> Function()? onReconnect;
  final Future<void> Function()? onRetry;
  final Map<String, dynamic>? metadata;

  _ChatBubble({
    required this.role,
    required this.text,
    this.isError = false,
    this.isStopped = false,
    this.thinkingText,
    this.thinkingDuration,
    this.isThinkingLive = false,
    this.onReconnect,
    this.onRetry,
    this.metadata,
  });
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }
}

class _TuningSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final String? tooltip;

  const _TuningSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (tooltip != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: tooltip!,
                    preferBelow: false,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 4),
                    child: Icon(Icons.info_outline, size: 14, color: const Color(0xFF6B7280)),
                  ),
                ],
              ],
            ),
            Text(
              format(value),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: NeoTheme.green,
            thumbColor: NeoTheme.green,
            overlayColor: NeoTheme.green.withValues(alpha: 0.12),
            inactiveTrackColor: const Color(0xFF374151),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ThinkingZone extends StatefulWidget {
  final String text;
  final Duration? duration;
  final bool isLive;

  const _ThinkingZone({
    required this.text,
    this.duration,
    this.isLive = false,
  });

  @override
  State<_ThinkingZone> createState() => _ThinkingZoneState();
}

class _ThinkingZoneState extends State<_ThinkingZone> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final durationLabel = widget.duration != null
        ? '${widget.duration!.inSeconds}s'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                if (widget.isLive)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF8B5CF6),
                    ),
                  )
                else
                  const Icon(Icons.psychology_rounded, size: 14, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                Text(
                  widget.isLive
                      ? 'Thinking…'
                      : 'Thought for $durationLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
                if (!widget.isLive) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ],
            ),
          ),
          if (widget.isLive || _expanded)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: BoxConstraints(
                maxHeight: widget.isLive ? 80 : 300,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
              ),
              child: SingleChildScrollView(
                reverse: widget.isLive,
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  widget.text,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF9CA3AF).withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
