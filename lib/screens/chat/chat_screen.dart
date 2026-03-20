import 'dart:math';

import 'package:flutter/material.dart';
import '../../services/bridge.dart';
import '../../services/chat_streaming_preference_store.dart';
import '../../theme.dart';

/// Default on-chain session length (seconds). Marketplace API often uses 1800.
const _defaultSessionSeconds = 3600;

class ChatScreen extends StatefulWidget {
  final String modelId;
  final String modelName;
  final bool isTEE;

  const ChatScreen({
    super.key,
    required this.modelId,
    required this.modelName,
    required this.isTEE,
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

  @override
  void initState() {
    super.initState();
    _loadStreamingPreference();
    _bootstrap();
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

  static const int _maxErrorDetailChars = 480;

  String _truncateDetail(String raw) {
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= _maxErrorDetailChars) return oneLine;
    return '${oneLine.substring(0, _maxErrorDetailChars)}…';
  }

  /// User-facing copy for common failures (rate limits, RPC congestion, WAF HTML).
  String _friendlySessionError(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Something went wrong while contacting the network.';
    }
    final lower = raw.toLowerCase();
    final detail = _truncateDetail(raw);

    final isCloudflareOrWaf = lower.contains('cloudflare') ||
        lower.contains('<!doctype html') ||
        lower.contains('just a moment') ||
        lower.contains('__cf_chl') ||
        (lower.contains('403') && lower.contains('forbidden'));
    if (isCloudflareOrWaf) {
      return 'A public RPC node returned a browser challenge (403 / Cloudflare) instead of JSON-RPC. '
          'That cannot be solved inside the app.\n\n'
          'RedPill will try other endpoints automatically — tap Retry. '
          'If this keeps happening, wait a minute and try again.\n\n'
          'Summary:\n$detail';
    }

    final noEthCall = lower.contains('eth_call') && lower.contains('not supported');
    if (noEthCall) {
      return 'That RPC endpoint does not support contract reads (eth_call). '
          'RedPill rotates through several Base nodes — tap Retry to use another.\n\n'
          'Summary:\n$detail';
    }

    final isRateLimited = lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('-32016') ||
        lower.contains('over rate limit');
    if (isRateLimited) {
      return 'The free Base RPC endpoints are rate-limiting requests right now.\n\n'
          'RedPill rotates across several public nodes and backs off automatically. '
          'Wait a few seconds, then tap Retry (or go back and open the chat again).\n\n'
          'Summary:\n$detail';
    }

    return _truncateDetail(raw);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = _BootstrapPhase.bootstrapping;
      _error = null;
    });
    try {
      final bridge = GoBridge();
      final convId = _newConversationId();
      bridge.createConversation(
        conversationId: convId,
        modelId: widget.modelId,
        modelName: widget.modelName,
        provider: '',
        isTEE: widget.isTEE,
      );
      final sess = bridge.openSession(widget.modelId, _defaultSessionSeconds, directPayment: false);
      final sid = sess['session_id'] as String?;
      if (sid == null || sid.isEmpty) {
        throw GoBridgeException('open session: missing session_id in response');
      }
      if (!mounted) return;
      setState(() {
        _conversationId = convId;
        _sessionId = sid;
        _phase = _BootstrapPhase.ready;
      });
    } on GoBridgeException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _phase = _BootstrapPhase.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _phase = _BootstrapPhase.error;
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final sid = _sessionId;
    final cid = _conversationId;
    if (text.isEmpty || sid == null || cid == null || _sending) return;

    setState(() {
      _messages.add(_ChatBubble(role: 'user', text: text));
      _input.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      final bridge = GoBridge();
      final res = bridge.sendPrompt(sid, cid, text, stream: _preferStreaming);
      final reply = res['response'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(role: 'assistant', text: reply.isEmpty ? '(empty response)' : reply));
        _sending = false;
      });
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(role: 'assistant', text: 'Error: ${e.message}', isError: true));
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(role: 'assistant', text: 'Error: $e', isError: true));
        _sending = false;
      });
    }
    _scrollToBottom();
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
                'TEE session',
                style: TextStyle(fontSize: 11, color: RedPillTheme.green.withValues(alpha: 0.85)),
              ),
          ],
        ),
      ),
      body: switch (_phase) {
        _BootstrapPhase.bootstrapping => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: RedPillTheme.green),
                SizedBox(height: 20),
                Text('Opening on-chain session…', style: TextStyle(color: Color(0xFF9CA3AF))),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'This can take a minute (MOR stake / network). Keep the app open.',
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _friendlySessionError(_error),
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.35),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _bootstrap, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        _BootstrapPhase.ready => Column(
            children: [
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
                        child: SelectableText(
                          b.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: b.isError ? const Color(0xFFFECACA) : null,
                            height: 1.35,
                          ),
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

enum _BootstrapPhase { bootstrapping, error, ready }

class _ChatBubble {
  final String role;
  final String text;
  final bool isError;

  _ChatBubble({required this.role, required this.text, this.isError = false});
}
