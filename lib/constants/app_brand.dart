/// User-facing product identity (title bar, lock screen, MaterialApp title, copy).
///
/// **Naming ideas** (pick one and set [displayName]):
/// - **Morpheus** — matches the public **Morpheus** inference network (default below).
///   App is **published by absgrafx** (`com.absgrafx.redpill`); protocol/repos may reference upstream MorpheusAIs on GitHub.
/// - **Lattice** — network / mesh inference vibe.
/// - **Veridian** — emerald brand, “signal in the noise.”
/// - **Ascent** — wings / upward motion.
/// - **Cipher** — privacy-forward without “lock” iconography in the name.
/// - **MorChat** — explicit “chat client” if you want a product-y suffix.
///
/// Internal Dart types (`RedPillApp`, `RedPillTheme`, package name `redpill`) stay as-is
/// until you intentionally rename the project; only [displayName] drives UI strings.
class AppBrand {
  AppBrand._();

  /// Shown next to [MorpheusLogo] on home, lock screen headline, dialogs, etc.
  static const String displayName = 'Morpheus';

  /// Wallet balance cards (home screen).
  static const String morBalanceHelper = 'MOR required to stake for inference';
  static const String ethBalanceHelper = 'ETH pays on-chain gas';

  /// HTTP User-Agent for RPC reachability checks ([RpcEndpointValidator]).
  static const String rpcCheckUserAgent = 'RedPill-RPC-Check/1.0 (absgrafx)';
}
