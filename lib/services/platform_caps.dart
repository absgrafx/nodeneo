import 'dart:io' show Platform;

/// Runtime platform capability checks.
///
/// Desktop platforms expose the full feature set (Developer API, AI Gateway,
/// API keys, MCP server). Mobile platforms show only consumer features plus
/// Blockchain Connection configuration.
///
/// Capability gating lives here. **Layout** decisions (column counts,
/// tile density, nav style) belong in `lib/services/form_factor.dart`.
class PlatformCaps {
  PlatformCaps._();

  static bool get isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  /// macOS / iOS — the Apple platforms, which share Keychain-backed
  /// secure storage and iCloud Keychain sync.
  static bool get isApple => Platform.isMacOS || Platform.isIOS;

  static bool get supportsBlockchainConfig => true;
  static bool get supportsDeveloperApi => isDesktop;
  static bool get supportsGateway => isDesktop;
  static bool get supportsApiKeys => supportsGateway;
  static bool get supportsMcp => isDesktop;

  /// Reveal a path in the platform's file manager (Finder on macOS).
  /// No Linux/Windows equivalent wired yet, so macOS-only for now.
  static bool get supportsRevealInFileManager => Platform.isMacOS;

  /// iCloud Keychain sync — Apple-only, backed by the platform's
  /// Keychain API on macOS and iOS.
  static bool get supportsIcloudKeychainSync => isApple;
}
