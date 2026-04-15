import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bridge.dart';

/// Default on-chain session length for new chats (seconds).
/// Stored in SQLite preferences (backed up with conversations).
class SessionDurationStore {
  SessionDurationStore._();
  static final SessionDurationStore instance = SessionDurationStore._();

  static const _prefKey = 'session_duration_seconds';
  static const _legacyFileName = 'default_session_duration_seconds.txt';

  static const int defaultSeconds = 3600;
  static const int minSeconds = 600;
  static const int maxSeconds = 86400;

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

  bool _migrated = false;

  static int clampSeconds(int s) => s.clamp(minSeconds, maxSeconds).toInt();

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
    try {
      await _migrateFromFileIfNeeded();
      final raw = GoBridge().getPreference(_prefKey);
      if (raw.isEmpty) return defaultSeconds;
      final v = int.tryParse(raw);
      if (v == null) return defaultSeconds;
      return snapToNearestPreset(v);
    } catch (_) {
      return defaultSeconds;
    }
  }

  Future<void> writeSeconds(int seconds) async {
    final s = snapToNearestPreset(seconds);
    try {
      GoBridge().setPreference(_prefKey, '$s');
    } catch (_) {}
  }

  Future<void> _migrateFromFileIfNeeded() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final d = await getApplicationSupportDirectory();
      final f = File('${d.path}${Platform.pathSeparator}nodeneo${Platform.pathSeparator}$_legacyFileName');
      if (!await f.exists()) return;
      final raw = (await f.readAsString()).trim();
      final existing = GoBridge().getPreference(_prefKey);
      if (existing.isEmpty && raw.isNotEmpty) {
        GoBridge().setPreference(_prefKey, raw);
      }
      await f.delete();
    } catch (_) {}
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
