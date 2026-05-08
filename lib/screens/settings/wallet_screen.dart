import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/external_links.dart';
import '../../services/bridge.dart';
import '../../services/form_factor.dart';
import '../../theme.dart';
import '../../utils/session_open_errors.dart';
import '../../widgets/section_card.dart';
import '../../widgets/session_close_flow.dart';
import '../wallet/wallet_security_actions.dart';

Map<String, dynamic> _scanWalletMorSync(void _) => GoBridge().scanWalletMOR();

/// Wallet screen: key management + active on-chain sessions.
class WalletScreen extends StatefulWidget {
  /// When true, kick off the "Where's My MOR?" scan immediately on open
  /// instead of waiting for the user to tap the section. Used by the wallet
  /// card's purple deep-link pill on the home screen so the user lands
  /// directly in a running scan.
  final bool autoRunScan;

  const WalletScreen({super.key, this.autoRunScan = false});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  // --- MOR scanner state ---
  bool _scanning = false;
  bool _withdrawing = false;
  Map<String, dynamic>? _scanResult;
  String? _scanError;

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
    _refreshSessions();
    if (widget.autoRunScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runScan();
      });
    }
  }

  // ── MOR scanner ──────────────────────────────────────────────

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final result = await compute(_scanWalletMorSync, null);
      if (!mounted) return;
      if (result['error'] != null) {
        setState(() {
          _scanError = result['error'] as String;
          _scanning = false;
        });
      } else {
        setState(() {
          _scanResult = result;
          _scanning = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanError = e.toString();
        _scanning = false;
      });
    }
  }

  Future<void> _recoverTokens() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recover on-hold MOR?'),
        content: const Text(
          'This sends an on-chain transaction to withdraw claimable MOR '
          'from the Inference Contract back to your wallet.\n\n'
          'Only tokens past the timelock period will be released. '
          'Requires ETH for gas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _withdrawing = true);
    try {
      final result = GoBridge().withdrawUserStakes();
      final txHash = result['tx_hash'] as String? ?? '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              txHash.isNotEmpty
                  ? 'Transaction sent: ${txHash.substring(0, 10)}...'
                  : 'Recovery transaction submitted',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        await _runScan();
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recovery failed: ${e.message}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
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
    final end = DateTime.fromMillisecondsSinceEpoch(
      sec * 1000,
      isUtc: true,
    ).toLocal();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sessionCloseErrorMessage(e.message)),
            duration: const Duration(seconds: 8),
          ),
        );
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
        errors.add(
          '${sid.substring(0, 8)}…: ${sessionCloseErrorMessage(e.message)}',
        );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _sessionsLoading || _closingAll
                ? null
                : _refreshSessions,
          ),
        ],
      ),
      body: MaxContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionCard(
              icon: Icons.key_outlined,
              title: 'Key Management',
              accentColor: NeoTheme.amber,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsCard(
                    icon: Icons.key_outlined,
                    iconColor: NeoTheme.amber,
                    title: 'Export Private Key',
                    subtitle: 'For use with MetaMask, Rabby, or other wallets',
                    onTap: () => showExportPrivateKeyFlow(context),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: NeoTheme.amber.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Never share your private key with anyone.',
                            style: TextStyle(
                              fontSize: 11,
                              color: NeoTheme.amber.withValues(alpha: 0.8),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              icon: Icons.account_balance_outlined,
              title: "Where's My MOR",
              status: _scanResult != null
                  ? StatusPill(
                      active: true,
                      label: '${_scanResult!['total']} MOR',
                    )
                  : const StatusPill(active: false, label: 'Tap to scan'),
              onExpand: _scanResult == null && !_scanning ? _runScan : null,
              child: _buildMorScannerBody(theme),
            ),
            const SizedBox(height: 12),
            SectionCard(
              icon: Icons.link_rounded,
              title: 'Active Sessions',
              status: StatusPill(
                active: _sessions.isNotEmpty,
                label: _sessionsLoading
                    ? '...'
                    : _sessions.isEmpty
                    ? 'None'
                    : '${_sessions.length} active',
              ),
              child: _buildSessionsBody(theme),
            ),
            const SizedBox(height: 16),
            // Quiet escape hatch into the long-form crypto walkthrough
            // on nodeneo.ai. Anyone landing here who isn't sure what
            // ETH-for-gas / MOR-for-stake actually means gets one tap
            // to a 25-minute primer instead of being stuck staring at
            // a wallet they don't yet understand. Sized small on
            // purpose so it doesn't compete with the primary key /
            // session affordances above.
            Center(
              child: TextButton.icon(
                onPressed: () => ExternalLinks.launch(
                  ExternalLinks.onramp,
                  context: context,
                ),
                icon: const Icon(Icons.school_outlined, size: 16),
                label: const Text(
                  'New to crypto? See the walkthrough',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: NeoTheme.emerald,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMorScannerBody(ThemeData theme) {
    if (_scanning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: NeoTheme.green,
                strokeWidth: 2.5,
              ),
              const SizedBox(height: 14),
              const Text(
                'Scanning on-chain sessions…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFD1D5DB),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Checking balances, active stakes, and on-hold positions',
                style: TextStyle(
                  fontSize: 11,
                  color: NeoTheme.green.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_scanError != null) {
      return Column(
        children: [
          Text(
            _scanError!,
            style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _runScan,
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    if (_scanResult == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Read-only on-chain scan showing your MOR across three buckets: '
            'in your wallet, staked in active sessions, and on hold after early closes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _runScan,
              style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Scan wallet'),
            ),
          ),
        ],
      );
    }

    final r = _scanResult!;
    final availableWei = r['on_hold_available_wei'] as String? ?? '0';
    final hasClaimable = availableWei != '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NeoTheme.green.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NeoTheme.green.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                'Total accounted',
                style: TextStyle(
                  fontSize: 10,
                  color: NeoTheme.green.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${r['total']} MOR',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'JetBrains Mono',
                  color: Colors.white,
                ),
              ),
              if (r['incomplete'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Scanned ${r['scanned']} of ${r['total_sessions']} sessions (newest only)',
                    style: TextStyle(
                      fontSize: 10,
                      color: NeoTheme.amber.withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _morBucket(
                theme,
                label: 'In Wallet',
                value: r['wallet_balance'] as String? ?? '—',
                color: NeoTheme.green,
                subtitle: 'Spendable',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _morBucket(
                theme,
                label: 'Active (Staked)',
                value: r['active_stake'] as String? ?? '—',
                color: const Color(0xFFA855F7),
                subtitle: '${r['open_sessions'] ?? 0} open sessions',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _morBucket(
                theme,
                label: 'On Hold',
                value: r['on_hold_total'] as String? ?? '—',
                color: const Color(0xFFEAB308),
                subtitle:
                    'Claimable: ${r['on_hold_available'] ?? '0'} · Locked: ${r['on_hold_locked'] ?? '0'}',
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Tooltip(
                message:
                    'When you close a session early (before its scheduled end),\n'
                    'the contract may hold back part of your stake until the\n'
                    'next UTC day boundary. After that unlock time, tap\n'
                    '"Recover" to withdraw it to your wallet.\n\n'
                    'If a session expires naturally, your stake is returned\n'
                    'in the close transaction — no hold period.',
                preferBelow: false,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 8),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: hasClaimable && !_withdrawing ? _recoverTokens : null,
            style: FilledButton.styleFrom(
              backgroundColor: NeoTheme.green,
              disabledBackgroundColor: NeoTheme.green.withValues(alpha: 0.15),
            ),
            icon: _withdrawing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.arrow_downward,
                    size: 16,
                    color: hasClaimable
                        ? Colors.white
                        : const Color(0xFF6B7280),
                  ),
            label: Text(
              _withdrawing ? 'Recovering…' : 'Recover claimable MOR',
              style: TextStyle(
                color: hasClaimable ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        if ((r['expired_unclosed'] as int? ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NeoTheme.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: NeoTheme.amber.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r['expired_unclosed']} session(s) are past their end time but still open. '
                    'Close them from Active Sessions to reclaim stake.',
                    style: TextStyle(
                      fontSize: 10,
                      color: NeoTheme.amber.withValues(alpha: 0.85),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => launchUrl(
                Uri.parse('https://tech.mor.org/session.html'),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 13,
                      color: NeoTheme.green.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Session staking details',
                      style: TextStyle(
                        fontSize: 11,
                        color: NeoTheme.green.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _scanning ? null : _runScan,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Rescan', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _morBucket(
    ThemeData theme, {
    required String label,
    required String value,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value MOR',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_sessionsLoading && _sessions.length >= 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                      onPressed: _closing.isNotEmpty ? null : _confirmCloseAll,
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
            width: double.infinity,
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
            final modelName = _modelNames[modelKey] ?? _shortHex(modelHex);
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sid.length > 16
                                ? '${sid.substring(0, 10)}...${sid.substring(sid.length - 6)}'
                                : sid,
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
                      onPressed: busy ? null : () => _confirmClose(row),
                      style: TextButton.styleFrom(
                        foregroundColor: NeoTheme.red,
                      ),
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
              ),
            );
          }),

        const SizedBox(height: 4),
        Text(
          'Auto-close runs every 15 min in the background.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
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
              Icon(Icons.chevron_right, color: theme.hintColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
