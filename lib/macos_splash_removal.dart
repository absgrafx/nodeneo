import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native macOS overlay in [MainFlutterWindow]; must call native `remove` after Flutter can paint.
///
/// The [FlutterMethodChannel] must be retained on the Swift side; we also retry here because
/// merged UI/platform thread builds can delay channel readiness.
const MethodChannel _kMacosSplashChannel = MethodChannel('redpill/macos_splash');

void scheduleMacOsNativeSplashRemoval() {
  if (kIsWeb || !Platform.isMacOS) return;

  Future<void> attemptRemove(int tryIndex) async {
    try {
      await _kMacosSplashChannel.invokeMethod<void>('remove');
    } catch (_) {
      if (tryIndex >= 12) return;
      final delayMs = 40 + tryIndex * 35;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      await attemptRemove(tryIndex + 1);
    }
  }

  // Two frames: first layout, then merged-thread engine is ready for platform channels.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>(() => attemptRemove(0));
    });
  });
}
