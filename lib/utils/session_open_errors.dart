import 'dart:convert';

/// Human-first session open failure: [headline] in red in the UI; raw JSON only under "Technical details".
class SessionOpenErrorParts {
  const SessionOpenErrorParts({
    required this.headline,
    this.supporting,
    this.whatNext,
    required this.rawTechnical,
    this.showTechnicalSection = true,
  });

  /// Short, plain-language reason (show prominently, e.g. red).
  final String headline;

  /// Extra context without repeating the raw error.
  final String? supporting;

  /// Actionable hint (optional).
  final String? whatNext;

  /// Truncated original error for support / power users (expandable).
  final String rawTechnical;

  /// When false, hide the expansion tile (nothing useful beyond headline).
  final bool showTechnicalSection;
}

const int _maxTechnicalChars = 900;

String _truncateTechnical(String raw) {
  final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= _maxTechnicalChars) return oneLine;
  return '${oneLine.substring(0, _maxTechnicalChars)}…';
}

/// Pull `reason` strings from `no provider accepting session: [...]` JSON if present.
List<String> extractProviderFailureReasons(String raw) {
  final key = 'no provider accepting session:';
  final i = raw.toLowerCase().indexOf(key);
  if (i < 0) return const [];
  final j = raw.indexOf('[', i);
  if (j < 0) return const [];
  final end = _closingBracketIndex(raw, j);
  if (end < 0) return const [];
  try {
    final decoded = jsonDecode(raw.substring(j, end + 1));
    if (decoded is! List) return const [];
    final out = <String>[];
    for (final e in decoded) {
      if (e is Map && e['reason'] is String) {
        final r = (e['reason'] as String).trim();
        if (r.isNotEmpty) out.add(r);
      }
    }
    return out;
  } catch (_) {
    final sub = raw.substring(j);
    final re = RegExp(r'"reason"\s*:\s*"([^"]*)"');
    final out = <String>[];
    for (final m in re.allMatches(sub)) {
      final s = m.group(1)?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out;
  }
}

int _closingBracketIndex(String s, int openBracket) {
  var depth = 0;
  for (var k = openBracket; k < s.length; k++) {
    final ch = s[k];
    if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) return k;
    }
  }
  return -1;
}

bool _teeFailure(String lower) {
  return lower.contains('tee attestation') ||
      (lower.contains('register mismatch') && (lower.contains('rtmr') || lower.contains('measurement')));
}

bool _morFailure(String lower) {
  return lower.contains('erc20') &&
      (lower.contains('transfer amount exceeds balance') ||
          lower.contains('exceeds balance') ||
          lower.contains('insufficient balance'));
}

/// Primary API for chat UI and snackbars.
SessionOpenErrorParts explainSessionOpenError(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return SessionOpenErrorParts(
      headline: 'Could not reach the network.',
      supporting: 'Check your connection and try again.',
      rawTechnical: '',
      showTechnicalSection: false,
    );
  }

  final lower = raw.toLowerCase();
  final technical = _truncateTechnical(raw);
  final reasons = extractProviderFailureReasons(raw);
  final combinedReasons = reasons.join(' ').toLowerCase();
  final teeFromReasons = reasons.any((r) => _teeFailure(r.toLowerCase()));
  final tee = teeFromReasons || _teeFailure(lower) || _teeFailure(combinedReasons);

  if (_morFailure(lower)) {
    return SessionOpenErrorParts(
      headline: 'Not enough MOR for this stake (or the transfer was rejected).',
      supporting:
          'Compare “Estimated MOR moved” to “Your wallet MOR” above. The estimate uses the real on-chain formula — it can be higher than a simple price × time.',
      whatNext: 'Add MOR on Base, shorten the session, or pick a cheaper model.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('sessiontooshort') || lower.contains('session too short')) {
    return SessionOpenErrorParts(
      headline: 'This session length is too short for the network rules.',
      supporting:
          'The chain computes how long your stake lasts. With the current numbers, the session would be shorter than the minimum allowed.',
      whatNext: 'Try a longer session, more MOR, or a cheaper model.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('insufficient funds') ||
      (lower.contains('gas') && lower.contains('fee')) ||
      lower.contains('max fee per gas less than block base fee')) {
    return SessionOpenErrorParts(
      headline: 'Not enough ETH for gas on Base.',
      whatNext: 'Send a little ETH to this wallet for fees, then tap Retry.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('user denied') ||
      lower.contains('user rejected') ||
      lower.contains('rejected the request') ||
      (lower.contains('rejected') && lower.contains('signature'))) {
    return SessionOpenErrorParts(
      headline: 'The transaction was cancelled in the wallet.',
      whatNext: 'Tap Retry and approve the prompt when you’re ready.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('cloudflare') ||
      lower.contains('<!doctype html') ||
      lower.contains('just a moment') ||
      lower.contains('__cf_chl') ||
      (lower.contains('403') && lower.contains('forbidden'))) {
    return SessionOpenErrorParts(
      headline: 'The RPC node blocked the request (often a Cloudflare challenge).',
      whatNext: 'Wait a moment and tap Retry — RedPill rotates public Base endpoints.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('eth_call') && lower.contains('not supported')) {
    return SessionOpenErrorParts(
      headline: 'This RPC endpoint cannot read contracts.',
      whatNext: 'Tap Retry to try another node.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('-32016') ||
      lower.contains('over rate limit')) {
    return SessionOpenErrorParts(
      headline: 'The network is rate-limiting requests right now.',
      whatNext: 'Wait a few seconds and tap Retry.',
      rawTechnical: technical,
    );
  }

  if (tee) {
    return SessionOpenErrorParts(
      headline: 'Secure (TEE) verification failed.',
      supporting:
          'The provider did not pass the hardware attestation check (trusted build measurements). Fake or misconfigured TEE endpoints are blocked on purpose — same idea as the Morpheus web app.',
      whatNext: 'Use the non-Secure model variant, try another provider, or pick another model.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('tee ping failed') || lower.contains('did not report a version')) {
    return SessionOpenErrorParts(
      headline: 'Could not reach the provider’s Secure (TEE) service.',
      supporting: 'The app must talk to the provider’s TEE endpoint before opening a Secure session.',
      whatNext: 'Try again later, another model, or the non-Secure variant.',
      rawTechnical: technical,
    );
  }

  if (reasons.isNotEmpty) {
    final first = reasons.first;
    final fl = first.toLowerCase();
    String headline;
    String? supporting;
    if (fl.contains('no capacity') || fl.contains('queue') || fl.contains('busy')) {
      headline = 'The provider is full or temporarily unavailable.';
      supporting = first;
    } else if (fl.contains('http') && fl.contains('50')) {
      headline = 'The provider returned a server error.';
      supporting = _shortenProviderReason(first);
    } else {
      headline = 'The provider could not start this session.';
      supporting = _shortenProviderReason(first);
    }
    return SessionOpenErrorParts(
      headline: headline,
      supporting: supporting,
      whatNext: reasons.length > 1
          ? 'RedPill tried more than one provider; you can Retry or choose another model.'
          : 'Try Retry in a minute, or pick another model.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('no provider accepting session') ||
      lower.contains('no capacity') ||
      (lower.contains('failed to initiate session') && lower.contains('no capacity'))) {
    return SessionOpenErrorParts(
      headline: 'No provider accepted a new session for this model.',
      supporting: 'Often means GPUs are full or providers are offline — not a wallet problem.',
      whatNext: 'Retry shortly, pick another model, or continue a chat that already has an open session.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('execution reverted')) {
    return SessionOpenErrorParts(
      headline: 'The smart contract rejected the transaction.',
      supporting: 'Something in the on-chain step did not satisfy the contract (allowance, stake, timing, etc.).',
      whatNext: 'Check balances above, adjust session length, or try another model.',
      rawTechnical: technical,
    );
  }

  if (lower.contains('nonce too low') || lower.contains('replacement transaction')) {
    return SessionOpenErrorParts(
      headline: 'Wallet transaction ordering conflict.',
      whatNext: 'Wait for pending transactions, then tap Retry.',
      rawTechnical: technical,
    );
  }

  return SessionOpenErrorParts(
    headline: 'Could not open an on-chain session.',
    supporting: 'Something went wrong while staking or registering the session.',
    whatNext: 'Tap Retry. If it keeps failing, try another model or check Network settings.',
    rawTechnical: technical,
  );
}

/// Strip long prefixes so the “provider” line reads like a sentence.
String _shortenProviderReason(String s) {
  var t = s.trim();
  const cut = 'failed to initiate session:';
  final i = t.toLowerCase().indexOf(cut);
  if (i >= 0) {
    t = t.substring(i + cut.length).trim();
  }
  if (t.length > 280) {
    return '${t.substring(0, 277)}…';
  }
  return t;
}

/// Shorter single-paragraph text for [SnackBar]s.
String sessionOpenErrorSnackMessage(String? raw) {
  final p = explainSessionOpenError(raw);
  final sb = StringBuffer(p.headline);
  if (p.supporting != null && p.supporting!.trim().isNotEmpty) {
    sb.write(' ');
    sb.write(p.supporting!.trim());
  }
  var out = sb.toString().trim();
  if (out.length > 220) return '${out.substring(0, 217)}…';
  return out;
}
