import Flutter
import UIKit

// Workaround for Flutter issue #183900:
// https://github.com/flutter/flutter/issues/183900
//
// Flutter's *implicit* engine pattern (Main.storyboard instantiates a
// FlutterViewController and the engine is created lazily during viewDidLoad)
// crashes with SIGSEGV in `-[VSyncClient initWithTaskRunner:callback:]` on
// iOS 26 + ProMotion devices (iPhone 15/16/17 Pro). `viewDidLoad` fires
// before the engine shell is initialized, so `engine.platformTaskRunner` is
// a null `fml::RefPtr` and the dereference inside VSyncClient's init takes
// down the process before Dart ever starts. To the user this looks like the
// iOS native LaunchScreen hanging forever.
//
// We work around it with the *explicit* engine pattern: construct a
// FlutterEngine, run it, register plugins, then create a FlutterViewController
// bound to that fully-attached engine and install it as the scene's root view
// controller. Drop this file's body back to a bare `FlutterSceneDelegate`
// subclass once Flutter ships the upstream fix (PR #184639) in stable.
//
// Companion edits:
//   * `AppDelegate.swift` no longer conforms to FlutterImplicitEngineDelegate.
//   * `Info.plist` no longer references Main.storyboard for scene/window setup
//     (LaunchScreen.storyboard is still used for the iOS native splash).
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var flutterEngine: FlutterEngine?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    let engine = FlutterEngine(name: "io.absgrafx.nodeneo.engine")
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    flutterEngine = engine

    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(
      engine: engine,
      nibName: nil,
      bundle: nil
    )
    self.window = window
    window.makeKeyAndVisible()
  }
}
