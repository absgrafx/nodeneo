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

  /// Build channel for this binary. Set at compile time via
  /// `--dart-define=BUILD_CHANNEL=stable|preview` from the GitHub Actions
  /// workflows (stable on `main`, preview on `dev`). Local `flutter run`
  /// inherits the default `preview`, matching dev-branch CI behaviour.
  ///
  /// The displayed version differs by channel — see [formatVersion]. The
  /// underlying `CFBundleShortVersionString` / pubspec version is identical
  /// either way, so a build promoted from dev → main carries the same
  /// `X.Y.Z` and only the in-app display changes.
  static const String buildChannel = String.fromEnvironment(
    'BUILD_CHANNEL',
    defaultValue: 'preview',
  );

  /// True if this binary was produced from a `main`-branch release build.
  /// False for dev-branch CI builds and local `flutter run`.
  static bool get isStableBuild => buildChannel == 'stable';

  /// Formats the in-app version label per the build channel:
  ///
  ///   - stable  → `v3.4.0`
  ///   - preview → `v3.4.0+5`  (matches pubspec.yaml's `name+build` notation
  ///     and ASC's TestFlight `3.4.0 (5)` build-number convention)
  ///
  /// Use everywhere the version is shown to a human (About screen header,
  /// version row, settings drawer footer). The `+N` suffix on previews is
  /// the visual cue that distinguishes a CI/local preview build from a
  /// shipped release without anyone needing to know the word "dev".
  static String formatVersion(String version, String buildNumber) {
    if (isStableBuild || buildNumber.isEmpty) return 'v$version';
    return 'v$version+$buildNumber';
  }
}
