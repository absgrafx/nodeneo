import '../services/bridge.dart';
import 'token_amount.dart';

/// Parsed stake vs wallet for the session-open UI (matches on-chain formula for top-scored bid).
class SessionStakePanel {
  SessionStakePanel({
    required this.estimatedStakeMor,
    required this.walletMor,
    required this.shortfallWei,
    required this.footnotes,
  });

  final String estimatedStakeMor;
  final String walletMor;
  final BigInt shortfallWei;
  final List<String> footnotes;

  bool get hasShortfall => shortfallWei > BigInt.zero;
}

class SessionCostEstimate {
  SessionCostEstimate._();

  static Future<SessionStakePanel?> loadStakePanel(
    String modelId,
    int durationSeconds,
    GoBridge bridge,
  ) async {
    try {
      final est = bridge.estimateOpenSessionStake(modelId, durationSeconds, directPayment: false);
      final stakeWei = (est['stake_wei'] as String?)?.trim() ?? '';
      if (stakeWei.isEmpty) return null;

      final stakeB = BigInt.tryParse(stakeWei) ?? BigInt.zero;
      final estimatedStakeMor = formatWeiFixedDecimals(stakeWei, 2);

      final summary = bridge.getWalletSummary();
      final morBalWei = (summary['mor_balance'] as String?)?.trim() ?? '0';
      final balB = BigInt.tryParse(morBalWei) ?? BigInt.zero;
      final walletMor = formatWeiFixedDecimals(morBalWei, 2);

      final short = stakeB > balB ? stakeB - balB : BigInt.zero;

      final footnotes = <String>[
        'How it is calculated: (total MOR supply × top bid price × session length) ÷ today\'s emissions budget. '
            'That is why this number can be much larger than a simple "price × time" in MOR.',
        'Allowance: the app uses increaseAllowance on MOR for the diamond when your allowance is below about 3× this stake — '
            'not a one-shot tiny approve.',
        'If the network falls through to another provider, the stake can differ slightly; this matches the first (top-scored) bid.',
      ];

      return SessionStakePanel(
        estimatedStakeMor: estimatedStakeMor,
        walletMor: walletMor,
        shortfallWei: short,
        footnotes: footnotes,
      );
    } catch (_) {
      return null;
    }
  }
}
