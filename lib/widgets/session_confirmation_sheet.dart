import 'package:flutter/material.dart';

import '../services/bridge.dart';
import '../services/session_duration_store.dart';
import '../theme.dart';
import '../utils/token_amount.dart';

/// Result of the pre-session confirmation modal. `null` means the user
/// cancelled; a populated decision means they accepted the stake and want
/// to enter the chat screen with `durationSeconds`.
class SessionStartDecision {
  final int durationSeconds;
  const SessionStartDecision({required this.durationSeconds});
}

/// Shows the "are these the right settings?" modal before opening a chat.
///
/// The caller passes in the model's **hourly stake** (in wei) and the
/// current **wallet MOR balance** — both already known on the home screen
/// from the calibration pass. The modal derives every preset's stake as
/// a linear scale of hourly stake (no FFI), keeping the numbers identical
/// to what the home list showed for the tapped tile.
///
/// If [hourlyStakeWei] is null, the modal does one calibration call itself
/// so it still works when opened outside the home screen's cached context.
Future<SessionStartDecision?> showSessionConfirmation({
  required BuildContext context,
  required String modelId,
  required String modelName,
  required String modelType,
  required bool isTEE,
  BigInt? hourlyStakeWei,
  BigInt? walletMorWei,
  int? initialDurationSeconds,
}) {
  return showDialog<SessionStartDecision>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SessionConfirmationDialog(
      modelId: modelId,
      modelName: modelName,
      modelType: modelType,
      isTEE: isTEE,
      initialHourlyStakeWei: hourlyStakeWei,
      initialWalletMorWei: walletMorWei,
      initialDurationSeconds: initialDurationSeconds,
    ),
  );
}

class _SessionConfirmationDialog extends StatefulWidget {
  final String modelId;
  final String modelName;
  final String modelType;
  final bool isTEE;
  final BigInt? initialHourlyStakeWei;
  final BigInt? initialWalletMorWei;
  final int? initialDurationSeconds;

  const _SessionConfirmationDialog({
    required this.modelId,
    required this.modelName,
    required this.modelType,
    required this.isTEE,
    this.initialHourlyStakeWei,
    this.initialWalletMorWei,
    this.initialDurationSeconds,
  });

  @override
  State<_SessionConfirmationDialog> createState() =>
      _SessionConfirmationDialogState();
}

class _SessionConfirmationDialogState
    extends State<_SessionConfirmationDialog> {
  /// Hourly stake (wei) — same number the home tile showed. Stake for any
  /// preset duration is a linear scale of this value.
  BigInt? _hourlyStakeWei;
  BigInt _walletMorWei = BigInt.zero;
  int _selectedSeconds = SessionDurationStore.defaultSeconds;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final bridge = GoBridge();
    final storedDefault = widget.initialDurationSeconds ??
        await SessionDurationStore.instance.readSeconds();
    if (!mounted) return;

    // Wallet balance — caller may have already read it; otherwise ask the bridge.
    BigInt walletMorWei = widget.initialWalletMorWei ?? BigInt.zero;
    if (widget.initialWalletMorWei == null) {
      try {
        final summary = bridge.getWalletSummary();
        walletMorWei =
            BigInt.tryParse((summary['mor_balance'] as String?) ?? '0') ??
                BigInt.zero;
      } catch (_) {
        walletMorWei = BigInt.zero;
      }
    }

    // Hourly stake — caller already computed it on the home screen. When
    // absent, we self-calibrate with one FFI call so the modal works
    // standalone.
    BigInt? hourly = widget.initialHourlyStakeWei;
    if (hourly == null) {
      try {
        final est = bridge.estimateOpenSessionStake(
          widget.modelId,
          3600,
          directPayment: false,
        );
        final raw = (est['stake_wei'] as String?)?.trim() ?? '';
        hourly = BigInt.tryParse(raw);
      } catch (e) {
        _loadError = e.toString();
      }
    }

    if (!mounted) return;
    setState(() {
      _hourlyStakeWei = hourly;
      _walletMorWei = walletMorWei;
      _selectedSeconds = storedDefault;
      _loading = false;
    });
  }

  BigInt? _stakeFor(int seconds) {
    final hourly = _hourlyStakeWei;
    if (hourly == null) return null;
    return hourly * BigInt.from(seconds) ~/ BigInt.from(3600);
  }

  bool _affordable(int seconds) {
    final stake = _stakeFor(seconds);
    if (stake == null) return true; // unknown — don't block
    return _walletMorWei >= stake;
  }

  String _stakeLabel(int seconds) {
    final stake = _stakeFor(seconds);
    if (stake == null) return '—';
    return '${formatWeiFixedDecimals(stake.toString(), 2)} MOR';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedAffordable = _affordable(_selectedSeconds);
    final walletLabel = formatWeiFixedDecimals(_walletMorWei.toString(), 2);

    return AlertDialog(
      backgroundColor: NeoTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NeoTheme.mainPanelOutline(0.25)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: const Text('Start session'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: NeoTheme.green),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ModelHeader(
                    name: widget.modelName,
                    type: widget.modelType,
                    isTEE: widget.isTEE,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Session length',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  _DurationDropdown(
                    selected: _selectedSeconds,
                    hourlyStakeWei: _hourlyStakeWei,
                    walletMorWei: _walletMorWei,
                    onChanged: (v) => setState(() => _selectedSeconds = v),
                  ),
                  const SizedBox(height: 14),
                  _StakeSummary(
                    stakeLabel: _stakeLabel(_selectedSeconds),
                    walletLabel: walletLabel,
                    affordable: selectedAffordable,
                  ),
                  if (!selectedAffordable) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Wallet balance is below the estimated stake for this '
                      'duration. Pick a shorter session or add MOR.',
                      style: TextStyle(
                        fontSize: 12,
                        color: NeoTheme.red.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (_loadError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Stake estimate unavailable — you can still start, '
                      'but the number shown may be approximate.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_loading || !selectedAffordable)
              ? null
              : () => Navigator.of(context).pop(
                    SessionStartDecision(durationSeconds: _selectedSeconds),
                  ),
          style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
          child: const Text('Start chat'),
        ),
      ],
    );
  }
}

class _ModelHeader extends StatelessWidget {
  final String name;
  final String type;
  final bool isTEE;

  const _ModelHeader({
    required this.name,
    required this.type,
    required this.isTEE,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isTEE
                ? NeoTheme.green.withValues(alpha: 0.18)
                : NeoTheme.mainPanelFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isTEE
                  ? NeoTheme.green.withValues(alpha: 0.35)
                  : const Color(0xFF374151),
            ),
          ),
          child: Center(
            child: Text(
              isTEE ? '🛡️' : '🤖',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (type.isNotEmpty)
                    Text(
                      type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.hintColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                  if (type.isNotEmpty) const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isTEE
                          ? NeoTheme.green.withValues(alpha: 0.15)
                          : const Color(0xFF374151).withValues(alpha: 0.4),
                      border: Border.all(
                        color: isTEE
                            ? NeoTheme.green.withValues(alpha: 0.4)
                            : const Color(0xFF374151),
                      ),
                    ),
                    child: Text(
                      isTEE ? 'TEE · Private' : 'Standard',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isTEE
                            ? NeoTheme.green.withValues(alpha: 0.95)
                            : theme.hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DurationDropdown extends StatelessWidget {
  final int selected;
  final BigInt? hourlyStakeWei;
  final BigInt walletMorWei;
  final ValueChanged<int> onChanged;

  const _DurationDropdown({
    required this.selected,
    required this.hourlyStakeWei,
    required this.walletMorWei,
    required this.onChanged,
  });

  BigInt? _stakeFor(int seconds) {
    final hourly = hourlyStakeWei;
    if (hourly == null) return null;
    return hourly * BigInt.from(seconds) ~/ BigInt.from(3600);
  }

  bool _affordable(int seconds) {
    final stake = _stakeFor(seconds);
    if (stake == null) return true;
    return walletMorWei >= stake;
  }

  String _formatStake(int seconds) {
    final stake = _stakeFor(seconds);
    if (stake == null) return '—';
    return '${formatWeiFixedDecimals(stake.toString(), 2)} MOR';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<int>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dropdownColor: NeoTheme.surface,
      items: SessionDurationStore.presets.map(((String, int) preset) {
        final (label, seconds) = preset;
        final affordable = _affordable(seconds);
        final stake = _formatStake(seconds);
        final color = affordable ? null : theme.hintColor;
        return DropdownMenuItem<int>(
          value: seconds,
          enabled: affordable,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                affordable ? stake : '$stake (insufficient)',
                style: TextStyle(
                  fontSize: 11,
                  color: affordable
                      ? theme.hintColor
                      : NeoTheme.red.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) {
        if (v == null) return;
        if (!_affordable(v)) return;
        onChanged(v);
      },
    );
  }
}

class _StakeSummary extends StatelessWidget {
  final String stakeLabel;
  final String walletLabel;
  final bool affordable;

  const _StakeSummary({
    required this.stakeLabel,
    required this.walletLabel,
    required this.affordable,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NeoTheme.mainPanelFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: affordable
              ? NeoTheme.mainPanelOutline(0.3)
              : NeoTheme.red.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StakeRow(
            label: 'Estimated stake',
            value: stakeLabel,
            valueColor: affordable ? NeoTheme.platinum : NeoTheme.red,
          ),
          const SizedBox(height: 4),
          _StakeRow(
            label: 'Wallet balance',
            value: '$walletLabel MOR',
            valueColor: theme.hintColor,
            small: true,
          ),
        ],
      ),
    );
  }
}

class _StakeRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool small;

  const _StakeRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = TextStyle(
      fontSize: small ? 11 : 12,
      color: theme.hintColor,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = TextStyle(
      fontSize: small ? 11 : 13,
      fontFamily: 'JetBrains Mono',
      color: valueColor ?? NeoTheme.platinum,
      fontWeight: small ? FontWeight.w500 : FontWeight.w700,
    );
    return Row(
      children: [
        Text(label, style: labelStyle),
        const Spacer(),
        Text(value, style: valueStyle),
      ],
    );
  }
}
