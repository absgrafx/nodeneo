import 'dart:io' show Platform;

/// Runtime platform capability checks.
///
/// Desktop platforms expose the full feature set (Developer API, AI Gateway,
/// API keys, MCP server). Mobile platforms show only consumer features plus
/// Blockchain Connection configuration.
class PlatformCaps {
  PlatformCaps._();

  static bool get isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  static bool get supportsBlockchainConfig => true;
  static bool get supportsDeveloperApi => isDesktop;
  static bool get supportsGateway => isDesktop;
  static bool get supportsApiKeys => supportsGateway;
  static bool get supportsMcp => isDesktop;
}
