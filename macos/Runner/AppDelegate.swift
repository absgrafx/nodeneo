import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    rewireAboutMenuItem()
  }

  /// Rewires the standard "About <App>" menu item from `NSApplication.shared`
  /// to this delegate so we can suppress the `(N)` build-number parens on
  /// stable (main) releases. The default action `orderFrontStandardAboutPanel(_:)`
  /// is owned by NSApplication, so the responder chain resolves to it before
  /// reaching us — pointing the menu item directly at our selector is the
  /// cleanest override.
  private func rewireAboutMenuItem() {
    guard let mainMenu = NSApp.mainMenu, let appMenu = mainMenu.items.first?.submenu else {
      return
    }
    let standardAboutSelector = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
    for item in appMenu.items where item.action == standardAboutSelector {
      item.target = self
      item.action = #selector(showCustomAboutPanel(_:))
      break
    }
  }

  /// On stable builds the macOS workflow sets `CFBundleVersion` equal to
  /// `CFBundleShortVersionString` (e.g. both `3.5.0`). When we detect that
  /// equality at runtime we clear `applicationVersion` so AppKit renders
  /// just `Version 3.5.0` without trailing parens. On dev preview builds
  /// `CFBundleVersion` is the small integer build counter (1, 2, 3, …)
  /// which never matches the SemVer string, so the panel keeps the
  /// default `Version 3.5.0 (N)` rendering — useful for cross-referencing
  /// a downloaded preview against its TestFlight build number.
  @objc private func showCustomAboutPanel(_ sender: Any?) {
    let info = Bundle.main.infoDictionary
    let shortVersion = info?["CFBundleShortVersionString"] as? String ?? ""
    let bundleVersion = info?["CFBundleVersion"] as? String ?? ""
    var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
    if !shortVersion.isEmpty && shortVersion == bundleVersion {
      options[.applicationVersion] = ""
    }
    NSApp.orderFrontStandardAboutPanel(options: options)
  }
}
