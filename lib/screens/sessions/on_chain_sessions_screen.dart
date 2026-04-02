import 'package:flutter/material.dart';

import '../../services/bridge.dart';
import '../../theme.dart';
import '../../widgets/session_close_flow.dart';

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

    final ok = await confirmCloseOnChainSession(context);
    if (ok != true || !mounted) return;

    setState(() => _closing.add(sid));
    try {
      if (!mounted) return;
      await runCloseOnChainSessionFlow(context, sid);
      if (!mounted) return;
      await _refresh();
      if (mounted && _sessions.isEmpty) {
        Navigator.of(context).pop();
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _closing.remove(sid));
    }
  }

  bool _closingAll = false;

  Future<void> _confirmCloseAll() async {
    final count = _sessions.length;
    if (count == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close all sessions?'),
        content: Text(
          'This will close $count session${count != 1 ? 's' : ''} one at a time. '
          'Each close is a separate on-chain transaction (30–90s each). '
          'Staked MOR is returned per contract rules.\n\n'
          'Total time: roughly ${count * 30}–${count * 90} seconds.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
            child: Text('Close All ($count)'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _closingAll = true);
    final sessionsCopy = List<Map<String, dynamic>>.from(
      _sessions.map((s) => Map<String, dynamic>.from(s as Map)),
    );

    int closed = 0;
    final errors = <String>[];

    for (final row in sessionsCopy) {
      if (!mounted) break;
      final sid = row['id'] as String? ?? '';
      if (sid.isEmpty) continue;

      setState(() => _closing.add(sid));
      try {
        GoBridge().closeSession(sid);
        closed++;
      } on GoBridgeException catch (e) {
        errors.add('${sid.substring(0, 8)}…: ${e.message}');
      } catch (e) {
        errors.add('${sid.substring(0, 8)}…: $e');
      } finally {
        if (mounted) setState(() => _closing.remove(sid));
      }
    }

    if (mounted) {
      setState(() => _closingAll = false);
      await _refresh();

      if (mounted) {
        final msg = errors.isEmpty
            ? 'Closed $closed session${closed != 1 ? 's' : ''} successfully.'
            : 'Closed $closed of ${sessionsCopy.length}. ${errors.length} failed.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      if (mounted && _sessions.isEmpty) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          if (!_loading && _sessions.length >= 2)
            _closingAll
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NeoTheme.green),
                    ),
                  )
                : TextButton(
                    onPressed: _closing.isNotEmpty ? null : _confirmCloseAll,
                    child: Text(
                      'Close All (${_sessions.length})',
                      style: TextStyle(
                        color: _closing.isNotEmpty ? const Color(0xFF6B7280) : NeoTheme.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _closingAll ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NeoTheme.green))
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
                                            style: theme.textTheme.labelSmall?.copyWith(color: NeoTheme.green.withValues(alpha: 0.9)),
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
