import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme.dart';

/// Renders assistant text as Markdown; user as plain selectable text; errors as red.
/// Fenced code blocks get a **Copy** control (not the whole message).
Widget buildChatMessageBody(
  ThemeData theme, {
  required String role,
  required String text,
  bool isError = false,
}) {
  if (isError) {
    return SelectableText(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: const Color(0xFFFECACA),
        height: 1.35,
      ),
    );
  }
  if (role == 'assistant') {
    final sheet = MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.35, color: theme.colorScheme.onSurface),
      h1: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      strong: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      em: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'JetBrains Mono',
        fontSize: 13,
        backgroundColor: const Color(0xFF1E293B),
        color: const Color(0xFFE2E8F0),
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF94A3B8),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: NeoTheme.green.withValues(alpha: 0.45), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      blockSpacing: 10,
      listIndent: 22,
      // Custom `pre` builder draws the block; keep outer wrapper from adding a second frame.
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
    );
    return MarkdownBody(
      data: text.isEmpty ? '\u00a0' : text,
      selectable: true,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: <String, MarkdownElementBuilder>{
        'pre': _FencedCodeCopyBlockBuilder(),
      },
    );
  }
  return SelectableText(
    text,
    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
  );
}

String _plainTextFromPre(md.Element pre) {
  final b = StringBuffer();
  void walk(md.Node? n) {
    if (n == null) return;
    if (n is md.Text) b.write(n.text);
    if (n is md.Element) {
      for (final c in n.children ?? <md.Node>[]) {
        walk(c);
      }
    }
  }
  for (final c in pre.children ?? <md.Node>[]) {
    walk(c);
  }
  return b.toString();
}

class _FencedCodeCopyBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = _plainTextFromPre(element);
    final mono = preferredStyle?.copyWith(
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          height: 1.45,
        ) ??
        const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          height: 1.45,
          color: Color(0xFFE2E8F0),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: code.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy code'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF94A3B8),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(code, style: mono),
            ),
          ),
        ],
      ),
    );
  }
}
