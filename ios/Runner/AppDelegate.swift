import Flutter
import UIKit

// Plugin registration moved to SceneDelegate as part of the explicit-engine
// workaround for Flutter issue #183900 — see SceneDelegate.swift for the
// full rationale. AppDelegate stays as a vanilla FlutterAppDelegate so the
// app-level plugin lifecycle hooks (e.g. URL scheme handling, push tokens)
// continue to flow through Flutter's default forwarding chain.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
