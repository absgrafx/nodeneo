/// Format wei string (18 decimals) as **ETH-style** decimal: always token units, never gwei.
/// Trims trailing zeros; caps fractional part at [maxFractionDigits] (default 8).
String formatWeiAsEthDecimal(String weiStr, {int maxFractionDigits = 8}) {
  final wei = BigInt.tryParse(weiStr.trim());
  if (wei == null || wei == BigInt.zero) return '0';
  final one = BigInt.from(10).pow(18);
  final whole = wei ~/ one;
  var rem = wei % one;
  if (rem == BigInt.zero) return whole.toString();
  var frac = rem.toString().padLeft(18, '0');
  frac = frac.replaceFirst(RegExp(r'0+$'), '');
  if (frac.length > maxFractionDigits) {
    frac = frac.substring(0, maxFractionDigits).replaceFirst(RegExp(r'0+$'), '');
  }
  if (frac.isEmpty) return whole.toString();
  return '$whole.$frac';
}

/// Format wei as a token amount with exactly [fractionDigits] after the decimal (rounded half-up).
String formatWeiFixedDecimals(String weiStr, int fractionDigits) {
  if (fractionDigits < 0) fractionDigits = 0;
  final wei = BigInt.tryParse(weiStr.trim());
  if (wei == null || wei == BigInt.zero) {
    if (fractionDigits == 0) return '0';
    return '0.${'0' * fractionDigits}';
  }
  final one = BigInt.from(10).pow(18);
  final scale = BigInt.from(10).pow(fractionDigits);
  final half = one ~/ BigInt.from(2);
  final rounded = (wei * scale + half) ~/ one;
  final w = rounded ~/ scale;
  final frac = (rounded % scale).toString().padLeft(fractionDigits, '0');
  return '$w.$frac';
}

/// Normalize a user-typed amount (MetaMask-style: decimal point, optional grouping).
/// - `0,05` → `0.05`
/// - `1.234,56` (EU) → `1234.56`
/// - `1,234.56` (US) → `1234.56`
String normalizeHumanAmountInput(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s'), '').replaceAll('_', '');
  if (s.isEmpty) return s;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    if (lastDot > lastComma) {
      s = s.replaceAll(',', '');
    } else {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
  } else if (lastComma >= 0 && lastDot < 0) {
    s = s.replaceAll(',', '.');
  }
  return s;
}

/// Convert a human amount like `0.05` or `1.5` into wei (10^[decimals]).
/// Use [normalizeHumanAmountInput] first so commas / grouping match MetaMask-style entry.
BigInt? parseTokenAmountToWei(String input, {int decimals = 18}) {
  final s = normalizeHumanAmountInput(input);
  if (s.isEmpty) return null;
  if (s.startsWith('-')) return null;

  final parts = s.split('.');
  if (parts.length > 2) return null;

  final wholeStr = parts[0].isEmpty ? '0' : parts[0];
  final whole = BigInt.tryParse(wholeStr);
  if (whole == null) return null;

  var wei = whole * BigInt.from(10).pow(decimals);
  if (parts.length == 2) {
    var frac = parts[1];
    if (frac.isEmpty) {
      // "5." → whole tokens only
    } else {
      if (frac.length > decimals) {
        frac = frac.substring(0, decimals);
      }
      frac = frac.padRight(decimals, '0');
      final fracWei = BigInt.tryParse(frac);
      if (fracWei == null) return null;
      wei += fracWei;
    }
  }
  if (wei <= BigInt.zero) return null;
  return wei;
}

/// Human-readable label for a wei amount (for confirmations / receipts).
String formatWeiForSendPreview(BigInt wei, {required bool isMor}) {
  final s = wei.toString();
  return isMor ? formatWeiFixedDecimals(s, 2) : formatWeiAsEthDecimal(s);
}
