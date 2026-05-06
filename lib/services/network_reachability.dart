import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Best-effort "is the device actually online" probe. We do this **before**
/// hitting the Go SDK's `Init` so we can show a human-readable "No internet
/// connection" screen instead of the generic "SDK Init Failed (Edit Custom
/// RPC)" — that error reads as "your blockchain endpoint is wrong" to a
/// normal user, when in reality airplane mode is on or the Wi-Fi is down.
///
/// Strategy: a short DNS lookup against well-known anycast hostnames. If any
/// host resolves within [timeout] we treat the device as online. We don't
/// hit HTTP because TLS handshakes add latency and a successful DNS lookup
/// already proves DNS + UDP egress + the OS resolver is functional, which is
/// 99% of "do I have internet" in practice.
///
/// We deliberately probe multiple hosts so a single DNS provider hiccup
/// (Cloudflare DDOSed, corporate DNS misbehaving, etc.) doesn't false-positive
/// us into the offline screen.
///
/// In addition to the one-shot [isOnline] probe, this class exposes a
/// **process-wide [onlineNotifier]** that tracks the most recent probe
/// result. Long-lived screens (home, chat) listen to this so they can react
/// to online → offline transitions (e.g. on app resume from airplane mode)
/// without each having to run its own probe loop. The notifier defaults to
/// `null` ("unknown") and stays there until something calls [recheck] for the
/// first time.
class NetworkReachability {
  NetworkReachability._();

  /// Anycast / globally-distributed hostnames that should resolve from any
  /// public network. Order matters — first-success short-circuits.
  static const _canaryHosts = <String>[
    'cloudflare.com',
    'apple.com',
    'google.com',
  ];

  /// Last-known reachability state, app-wide. `null` = not yet probed.
  /// Updated by [recheck] (and by [isOnline] when called via [recheck]).
  static final ValueNotifier<bool?> onlineNotifier = ValueNotifier<bool?>(null);

  /// Returns `true` when at least one canary host resolves within [timeout].
  ///
  /// Defaults to a 3-second budget. In airplane mode this returns `false`
  /// almost immediately (the OS short-circuits the lookup with `SocketException:
  /// Failed host lookup`); on a flaky network it bounds the wait so the user
  /// isn't staring at a spinner for 30+ seconds.
  ///
  /// Does **not** update [onlineNotifier]. Use [recheck] when you want the
  /// app-wide state mutated.
  static Future<bool> isOnline({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    for (final host in _canaryHosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(timeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException catch (e) {
        AppLogger.info('[NetworkReachability] $host lookup failed: ${e.message}');
      } on TimeoutException {
        AppLogger.info('[NetworkReachability] $host lookup timed out');
      } catch (e) {
        AppLogger.info('[NetworkReachability] $host lookup error: $e');
      }
    }
    return false;
  }

  /// Convenience wrapper that probes via [isOnline] AND publishes the result
  /// to [onlineNotifier]. Returns the same boolean for callers that want to
  /// branch immediately on the result.
  static Future<bool> recheck({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final online = await isOnline(timeout: timeout);
    if (onlineNotifier.value != online) {
      onlineNotifier.value = online;
    }
    return online;
  }
}
