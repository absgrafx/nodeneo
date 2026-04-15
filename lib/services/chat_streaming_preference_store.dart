import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bridge.dart';

/// Persists whether chat completions should request provider streaming (SSE).
/// Stored in SQLite preferences (backed up with conversations).
class ChatStreamingPreferenceStore {
  ChatStreamingPreferenceStore._();
  static final ChatStreamingPreferenceStore instance = ChatStreamingPreferenceStore._();

  static const _prefKey = 'chat_streaming_preference';
  static const _legacyFileName = 'chat_streaming_preference.txt';

  static const bool defaultStreaming = true;

  bool _migrated = false;

  Future<bool> readPreferStreaming() async {
    try {
      await _migrateFromFileIfNeeded();
      final raw = GoBridge().getPreference(_prefKey);
      if (raw.isEmpty) return defaultStreaming;
      return raw != '0' && raw != 'false';
    } catch (_) {
      return defaultStreaming;
    }
  }

  Future<void> writePreferStreaming(bool value) async {
    try {
      GoBridge().setPreference(_prefKey, value ? '1' : '0');
    } catch (_) {}
  }

  Future<void> _migrateFromFileIfNeeded() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final d = await getApplicationSupportDirectory();
      final f = File('${d.path}${Platform.pathSeparator}nodeneo${Platform.pathSeparator}$_legacyFileName');
      if (!await f.exists()) return;
      final raw = (await f.readAsString()).trim().toLowerCase();
      final existing = GoBridge().getPreference(_prefKey);
      if (existing.isEmpty && raw.isNotEmpty) {
        final val = (raw == '0' || raw == 'false' || raw == 'off' || raw == 'no') ? '0' : '1';
        GoBridge().setPreference(_prefKey, val);
      }
      await f.delete();
    } catch (_) {}
  }
}
