import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/chain_config.dart';
import '../../services/bridge.dart';
import '../../theme.dart';

/// Lists on-chain inference sessions for this wallet that are still open
/// (`closed_at` == 0). Closing early runs a chain tx (may take a minute) and
/// coordinates with the provider to release stake.
class OnChainSessionsScreen extends StatefulWidget {
  const OnChainSessionsScreen({super.key});

  @override
  State<OnChainSessionsScreen> createState() => _OnChainSessionsScreenState();
}

class _OnChainSessionsScreenState extends State<OnChainSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _sessions = [];
  Map<String, String> _modelNames = {};
  final Set<String> _closing = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _normId(String? s) {
    if (s == null) return '';
    var x = s.toLowerCase().trim();
    if (x.startsWith('0x')) x = x.substring(2);
    return x;
  }

  Future<void> _loadModelNames() async {
    try {
      final models = GoBridge().getActiveModels(teeOnly: false);
      final map = <String, String>{};
      for (final m in models) {
        if (m is! Map) continue;
        final id = _normId(m['id'] as String?);
        final name = m['name'] as String? ?? id;
        if (id.isNotEmpty) map[id] = name;
      }
      if (mounted) setState(() => _modelNames = map);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _loadModelNames();
    try {
      final list = GoBridge().listUnclosedSessions();
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _loading = false;
      });
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _shortHex(String id) {
    if (id.length < 18) return id;
    return '${id.substring(0, 12)}…${id.substring(id.length - 8)}';
  }

  /// After a successful close, show tx hash + copy + Blockscout link.
  Future<void> _showCloseTransactionSheet(String txHash) async {
    final tx = txHash.trim();
    final url = tx.isNotEmpty ? blockscoutTransactionUrl(tx) : '';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: RedPillTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B5563),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  tx.isNotEmpty ? 'Close transaction submitted' : 'Session closed',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (tx.isNotEmpty) ...[
                  Text(
                    'Inspect on Base (Blockscout). Confirmation can take a short time.',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).hintColor, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    tx,
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Color(0xFFE5E7EB)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: tx));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Transaction hash copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    label: const Text('Copy hash'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: url.isEmpty
                        ? null
                        : () async {
                            final uri = Uri.parse(url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } else if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Open in browser: $url')),
                              );
                            }
                          },
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('View on Blockscout'),
                  ),
                ] else
                  Text(
                    'No transaction hash was returned. The session may still be closing — refresh the list in a moment.',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).hintColor, height: 1.35),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _endsSummary(String endsAtUnix) {
    final sec = int.tryParse(endsAtUnix.trim());
    if (sec == null || sec <= 0) return '—';
    final end = DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true).toLocal();
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 'Ended (close to reclaim stake)';
    if (left.inHours >= 1) return '${left.inHours}h ${left.inMinutes % 60}m left';
    if (left.inMinutes >= 1) return '${left.inMinutes}m left';
    return '${left.inSeconds}s left';
  }

  Future<void> _confirmClose(Map<String, dynamic> row) async {
    final sid = row['id'] as String? ?? '';
    if (sid.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close session on-chain?'),
        content: const Text(
          'This submits a close transaction and talks to the provider. '
          'It can take 30–90s. Stake is returned per contract rules.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _closing.add(sid));
    try {
      final res = GoBridge().closeSession(sid);
      final tx = res['tx_hash'] as String? ?? '';
      if (!mounted) return;
      await _showCloseTransactionSheet(tx);
      await _refresh();
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _closing.remove(sid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RedPillTheme.green))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _refresh, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No open on-chain sessions for this wallet.\n'
                          'After you chat, a session stays open until it expires or you close it here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (context, i) {
                        final row = _sessions[i] as Map<String, dynamic>;
                        final sid = row['id'] as String? ?? '';
                        final modelHex = row['model_agent_id'] as String? ?? '';
                        final modelKey = _normId(modelHex);
                        final modelName = _modelNames[modelKey] ?? _shortHex(modelHex);
                        final ends = row['ends_at'] as String? ?? '0';
                        final busy = _closing.contains(sid);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(modelName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          SelectableText(
                                            sid,
                                            style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: Color(0xFF6B7280)),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _endsSummary(ends),
                                            style: theme.textTheme.labelSmall?.copyWith(color: RedPillTheme.green.withValues(alpha: 0.9)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.tonal(
                                      onPressed: busy ? null : () => _confirmClose(row),
                                      child: busy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('Close'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
