import Cocoa
import FlutterMacOS

/// Brand splash: `flutter_native_splash` does not generate macOS targets (Android/iOS/Web only).
/// Keep midnight + `SplashLogo` in sync with `pubspec.yaml` `flutter_native_splash` color/image.
///
/// **Important:** retain [FlutterMethodChannel] for the lifetime of the window; a temporary
/// channel is deallocated and Dart's `invokeMethod('remove')` never reaches native code.
class MainFlutterWindow: NSWindow {
  private var splashContainer: NSView?
  /// Strong ref so the engine keeps the handler (see `lib/macos_splash_removal.dart`).
  private var macosSplashChannel: FlutterMethodChannel?
  private var splashFallbackTimer: Timer?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame

    let brandBg = NSColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)

    backgroundColor = brandBg
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)

    let flutterView = flutterViewController.view
    flutterView.wantsLayer = true
    flutterView.layer?.backgroundColor = brandBg.cgColor

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "nodeneo/macos_splash",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "remove" {
        self?.removeSplashOverlay()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    macosSplashChannel = channel

    DispatchQueue.main.async { [weak self] in
      self?.installSplashOverlay(flutterView: flutterView, brandBg: brandBg)
      self?.scheduleSplashFallbackRemoval()
    }

    super.awakeFromNib()

    self.minSize = NSSize(width: 480, height: 700)

    title = "Node Neo"
    DispatchQueue.main.async { [weak self] in
      self?.title = "Node Neo"
    }
  }

  /// If Dart never reaches the channel (regression), don't trap the user forever.
  private func scheduleSplashFallbackRemoval() {
    splashFallbackTimer?.invalidate()
    splashFallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
      self?.splashFallbackTimer = nil
      if self?.splashContainer != nil {
        self?.removeSplashOverlay()
      }
    }
  }

  private func installSplashOverlay(flutterView: NSView, brandBg: NSColor) {
    guard let image = NSImage(named: "SplashLogo") else { return }

    let container = NSView(frame: flutterView.bounds)
    container.wantsLayer = true
    container.layer?.backgroundColor = brandBg.cgColor
    container.autoresizingMask = [.width, .height]

    let imageView = NSImageView(frame: container.bounds)
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyDown
    imageView.imageAlignment = .alignCenter
    imageView.autoresizingMask = [.width, .height]

    container.addSubview(imageView)
    flutterView.addSubview(container)
    splashContainer = container
  }

  private func removeSplashOverlay() {
    splashFallbackTimer?.invalidate()
    splashFallbackTimer = nil

    guard let splash = splashContainer else { return }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.22
      splash.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      splash.removeFromSuperview()
      self?.splashContainer = nil
    })
  }
}
