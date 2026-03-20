import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Default on-chain session length for new chats (seconds). Persisted locally.
class SessionDurationStore {
  SessionDurationStore._();
  static final SessionDurationStore instance = SessionDurationStore._();

  static const _fileName = 'default_session_duration_seconds.txt';

  static const int defaultSeconds = 3600;
  /// On-chain sessions use stake math; very short requests can revert with SessionTooShort()
  /// even when the contract’s nominal min is 5m — 10m+ is a safer floor for the UI.
  static const int minSeconds = 600;
  static const int maxSeconds = 86400;

  /// Presets shown in UI (label, seconds).
  static const List<(String label, int seconds)> presets = <(String, int)>[
    ('10 minutes', 600),
    ('15 minutes', 900),
    ('30 minutes', 1800),
    ('1 hour', 3600),
    ('2 hours', 7200),
    ('4 hours', 14400),
    ('8 hours', 28800),
    ('24 hours', 86400),
  ];

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}redpill');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static int clampSeconds(int s) => s.clamp(minSeconds, maxSeconds).toInt();

  /// If stored value is not a preset, snap to nearest preset so dropdowns stay consistent.
  static int snapToNearestPreset(int s) {
    s = clampSeconds(s);
    var best = defaultSeconds;
    var bestDiff = 1 << 30;
    for (final (_, sec) in presets) {
      final d = (sec - s).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = sec;
      }
    }
    return best;
  }

  Future<int> readSeconds() async {
    final f = await _file();
    if (!await f.exists()) return defaultSeconds;
    final v = int.tryParse((await f.readAsString()).trim());
    if (v == null) return defaultSeconds;
    return snapToNearestPreset(v);
  }

  Future<void> writeSeconds(int seconds) async {
    final s = snapToNearestPreset(seconds);
    final f = await _file();
    await f.writeAsString('$s', flush: true);
  }

  static String formatDurationLabel(int seconds) {
    if (seconds % 3600 == 0 && seconds >= 3600) {
      final h = seconds ~/ 3600;
      return h == 1 ? '1 hour' : '$h hours';
    }
    if (seconds % 60 == 0) {
      final m = seconds ~/ 60;
      return m == 1 ? '1 minute' : '$m minutes';
    }
    return '$seconds seconds';
  }
}
