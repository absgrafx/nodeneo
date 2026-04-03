import 'package:flutter/material.dart';

import '../../services/bridge.dart';
import '../../services/session_duration_store.dart';
import '../../theme.dart';
import '../../utils/session_open_errors.dart';
import '../../widgets/session_close_flow.dart';

/// Combined Sessions screen: default duration picker + active on-chain sessions.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  // --- Duration state ---
  bool _durationLoading = true;
  int _sessionDurationSeconds = SessionDurationStore.defaultSeconds;

  // --- On-chain sessions state ---
  bool _sessionsLoading = true;
  String? _sessionsError;
  List<dynamic> _sessions = [];
  Map<String, String> _modelNames = {};
  final Set<String> _closing = {};
  bool _closingAll = false;

  @override
  void initState() {
    super.initState();
    _loadDuration();
    _refreshSessions();
  }

  // ── Duration ──────────────────────────────────────────────────

  Future<void> _loadDuration() async {
    final sec = await SessionDurationStore.instance.readSeconds();
    if (!mounted) return;
    setState(() {
      _sessionDurationSeconds = sec;
      _durationLoading = false;
    });
  }

  Future<void> _saveDuration(int seconds) async {
    await SessionDurationStore.instance.writeSeconds(seconds);
    if (!mounted) return;
    setState(() => _sessionDurationSeconds = seconds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Default session: ${SessionDurationStore.formatDurationLabel(seconds)}',
        ),
      ),
    );
  }

  // ── On-chain sessions ─────────────────────────────────────────

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

  Future<void> _refreshSessions() async {
    setState(() {
      _sessionsLoading = true;
      _sessionsError = null;
    });
    await _loadModelNames();
    try {
      final list = GoBridge().listUnclosedSessions();
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _sessionsLoading = false;
      });
    } on GoBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionsError = e.message;
        _sessionsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionsError = e.toString();
        _sessionsLoading = false;
      });
    }
  }

  String _shortHex(String id) {
    if (id.length < 18) return id;
    return '${id.substring(0, 12)}...${id.substring(id.length - 8)}';
  }

  String _endsSummary(String endsAtUnix) {
    final sec = int.tryParse(endsAtUnix.trim());
    if (sec == null || sec <= 0) return '—';
    final end =
        DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true).toLocal();
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 'Ended (close to reclaim stake)';
    if (left.inHours >= 1) {
      return '${left.inHours}h ${left.inMinutes % 60}m left';
    }
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
      await _refreshSessions();
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sessionCloseErrorMessage(e.message)),
          duration: const Duration(seconds: 8),
        ));
      }
    } finally {
      if (mounted) setState(() => _closing.remove(sid));
    }
  }

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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
        errors.add('${sid.substring(0, 8)}…: ${sessionCloseErrorMessage(e.message)}');
      } catch (e) {
        errors.add('${sid.substring(0, 8)}…: $e');
      } finally {
        if (mounted) setState(() => _closing.remove(sid));
      }
    }

    if (mounted) {
      setState(() => _closingAll = false);
      await _refreshSessions();

      if (mounted) {
        final msg = errors.isEmpty
            ? 'Closed $closed session${closed != 1 ? 's' : ''} successfully.'
            : 'Closed $closed of ${sessionsCopy.length}. ${errors.length} failed.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                _sessionsLoading || _closingAll ? null : _refreshSessions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Section 1: Default Duration ──
          const _SectionBanner(title: 'Default Duration'),
          const SizedBox(height: 16),
          if (_durationLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: NeoTheme.green),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NeoTheme.mainPanelFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NeoTheme.mainPanelOutline()),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Session Length',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, sec)
                          in SessionDurationStore.presets)
                        ChoiceChip(
                          label: Text(label),
                          selected: _sessionDurationSeconds == sec,
                          onSelected: (_) => _saveDuration(sec),
                          selectedColor:
                              NeoTheme.green.withValues(alpha: 0.18),
                          side: BorderSide(
                            color: _sessionDurationSeconds == sec
                                ? NeoTheme.green.withValues(alpha: 0.5)
                                : const Color(0xFF374151),
                          ),
                          labelStyle: TextStyle(
                            color: _sessionDurationSeconds == sec
                                ? NeoTheme.green
                                : const Color(0xFF9CA3AF),
                            fontWeight: _sessionDurationSeconds == sec
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'How long each on-chain chat session lasts. Affects estimated MOR stake.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Section 2: Active Sessions ──
          const _SectionBanner(title: 'Active Sessions'),
          if (!_sessionsLoading && _sessions.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: _closingAll
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NeoTheme.green,
                        ),
                      )
                    : TextButton(
                        onPressed:
                            _closing.isNotEmpty ? null : _confirmCloseAll,
                        child: Text(
                          'Close All (${_sessions.length})',
                          style: TextStyle(
                            color: _closing.isNotEmpty
                                ? const Color(0xFF6B7280)
                                : NeoTheme.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 12),

          if (_sessionsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: NeoTheme.green),
              ),
            )
          else if (_sessionsError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sessionsError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refreshSessions,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NeoTheme.mainPanelFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NeoTheme.mainPanelOutline()),
              ),
              child: Text(
                'No open on-chain sessions.\nSessions appear here after you start a chat.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  height: 1.4,
                ),
              ),
            )
          else
            ...List.generate(_sessions.length, (i) {
              final row = _sessions[i] as Map<String, dynamic>;
              final sid = row['id'] as String? ?? '';
              final modelHex = row['model_agent_id'] as String? ?? '';
              final modelKey = _normId(modelHex);
              final modelName =
                  _modelNames[modelKey] ?? _shortHex(modelHex);
              final ends = row['ends_at'] as String? ?? '0';
              final busy = _closing.contains(sid);
              final endText = _endsSummary(ends);
              final isExpired = endText.startsWith('Ended');

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NeoTheme.mainPanelFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NeoTheme.mainPanelOutline()),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isExpired
                              ? const Color(0xFF6B7280)
                              : NeoTheme.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelName,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${sid.length > 16 ? '${sid.substring(0, 10)}...${sid.substring(sid.length - 6)}' : sid}',
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              endText,
                              style: TextStyle(
                                fontSize: 11,
                                color: isExpired
                                    ? NeoTheme.amber
                                    : NeoTheme.green.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed:
                            busy ? null : () => _confirmClose(row),
                        style: TextButton.styleFrom(
                          foregroundColor: NeoTheme.red,
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Close'),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Auto-close runs every 15 min in the background.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full-width section banner ──────────────────────────────────

class _SectionBanner extends StatelessWidget {
  final String title;

  const _SectionBanner({required this.title});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 36,
      child: Transform.translate(
        offset: const Offset(-20, 0),
        child: OverflowBox(
          maxWidth: screenW,
          maxHeight: 36,
          alignment: Alignment.centerLeft,
          child: Container(
            width: screenW,
            color: NeoTheme.amber.withValues(alpha: 0.08),
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: NeoTheme.amber.withValues(alpha: 0.90),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
