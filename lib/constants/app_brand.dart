/// User-facing product identity (title bar, lock screen, MaterialApp title, copy).
///
/// **Node Neo** — decentralised AI inference client.
/// Powered by the Morpheus DeAI Network.
/// Published by ABSGrafx LLC (com.absgrafx.nodeneo).
class AppBrand {
  AppBrand._();

  /// Shown on home screen, lock screen, dialogs, window title.
  static const String displayName = 'Node Neo';

  /// Tagline shown on onboarding / about screens.
  static const String tagline = 'Powered by Morpheus DeAI Network';

  /// Wallet balance cards (home screen).
  static const String morBalanceHelper = 'Stake for inference';
  static const String ethBalanceHelper = 'Pays on-chain gas';

  /// HTTP User-Agent for RPC reachability checks.
  static const String rpcCheckUserAgent = 'NodeNeo-RPC-Check/1.0';
}
