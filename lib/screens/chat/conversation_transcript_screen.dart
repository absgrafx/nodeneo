import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/bridge.dart';
import '../../theme.dart';
import '../../widgets/chat_message_body.dart';
import 'chat_screen.dart';

/// Read-only message list; use **Continue** to return to chat (same on-chain session if [onChainSessionId] is set).
class ConversationTranscriptScreen extends StatefulWidget {
  final String conversationId;
  final String modelId;
  final String modelName;
  final bool isTEE;

  /// When non-empty, [ChatScreen] resumes this MOR session instead of waiting for a new one on send.
  final String? onChainSessionId;

  const ConversationTranscriptScreen({
    super.key,
    required this.conversationId,
    required this.modelId,
    required this.modelName,
    this.isTEE = false,
    this.onChainSessionId,
  });

  @override
  State<ConversationTranscriptScreen> createState() => _ConversationTranscriptScreenState();
}

class _ConversationTranscriptScreenState extends State<ConversationTranscriptScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bridge = GoBridge();
      final raw = bridge.getMessages(widget.conversationId);
      final list = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _continueThread() {
    if (widget.modelId.isEmpty) return;
    final sid = widget.onChainSessionId?.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          modelId: widget.modelId,
          modelName: widget.modelName,
          isTEE: widget.isTEE,
          resumeConversationId: widget.conversationId,
          resumeSessionId: (sid != null && sid.isNotEmpty) ? sid : null,
        ),
      ),
    );
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
            Text(
              'History (read-only)',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: RedPillTheme.green))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Color(0xFFF87171))),
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(child: Text('No messages saved.', style: TextStyle(color: Color(0xFF6B7280))))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) {
                              final m = _messages[i];
                              final role = m['role'] as String? ?? '';
                              final text = m['content'] as String? ?? '';
                              final isUser = role == 'user';
                              return Align(
                                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? RedPillTheme.green.withValues(alpha: 0.12)
                                        : RedPillTheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF374151)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isUser)
                                        Row(
                                          children: [
                                            const Spacer(),
                                            IconButton(
                                              tooltip: 'Copy message',
                                              padding: EdgeInsets.zero,
                                              visualDensity: VisualDensity.compact,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              icon: Icon(
                                                Icons.copy_rounded,
                                                size: 18,
                                                color: theme.hintColor,
                                              ),
                                              onPressed: text.isEmpty
                                                  ? null
                                                  : () async {
                                                      await Clipboard.setData(ClipboardData(text: text));
                                                      if (!ctx.mounted) return;
                                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                                        const SnackBar(
                                                          content: Text('Message copied'),
                                                          behavior: SnackBarBehavior.floating,
                                                          duration: Duration(seconds: 2),
                                                        ),
                                                      );
                                                    },
                                            ),
                                          ],
                                        ),
                                      buildChatMessageBody(
                                        theme,
                                        role: role,
                                        text: text,
                                        isError: false,
                                      ),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    (widget.onChainSessionId != null && widget.onChainSessionId!.trim().isNotEmpty)
                        ? 'Resume uses your open on-chain session. Prior messages stay in context.'
                        : 'A new on-chain session starts when you send. Prior messages stay in context.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loading || widget.modelId.isEmpty ? null : _continueThread,
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                    icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                    label: const Text('Continue chatting'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
