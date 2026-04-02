import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists whether chat completions should request provider streaming (SSE).
/// Applies to all models and sessions until changed.
class ChatStreamingPreferenceStore {
  ChatStreamingPreferenceStore._();
  static final ChatStreamingPreferenceStore instance = ChatStreamingPreferenceStore._();

  static const _fileName = 'chat_streaming_preference.txt';

  /// Default: streaming on (matches typical marketplace / proxy-router usage).
  static const bool defaultStreaming = true;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// `true` = request streaming from provider; `false` = one-shot completion.
  Future<bool> readPreferStreaming() async {
    final f = await _file();
    if (!await f.exists()) return defaultStreaming;
    final s = (await f.readAsString()).trim().toLowerCase();
    if (s == '0' || s == 'false' || s == 'off' || s == 'no') {
      return false;
    }
    return true;
  }

  Future<void> writePreferStreaming(bool value) async {
    final f = await _file();
    await f.writeAsString(value ? '1' : '0', flush: true);
  }
}
