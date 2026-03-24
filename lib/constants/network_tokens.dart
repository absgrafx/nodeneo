/// User-facing labels for the default chain (Base mainnet) and assets.
///
/// Central place so wallet, chat stakes, and settings stay consistent (MVP item 9).
abstract final class NetworkTokens {
  /// Network name shown next to balances and in wallet chrome.
  static const String networkName = 'Base';

  /// Longer label for headers / settings copy.
  static const String networkMainnetLabel = 'Base mainnet';

  /// Native gas token on Base.
  static const String ethSymbol = 'ETH';

  /// Morpheus token (ERC-20 on Base).
  static const String morSymbol = 'MOR';

  /// e.g. "ETH · Base" for chips and summaries.
  static String ethWithNetwork() => '$ethSymbol · $networkName';

  /// e.g. "MOR · Base"
  static String morWithNetwork() => '$morSymbol · $networkName';

  /// Subtitle under an amount (small grey line).
  static const String balanceNetworkHint = 'on Base';
}
