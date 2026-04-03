import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the user's iCloud Keychain sync preference (on/off).
/// Default: off (device-only) — user explicitly opts in.
class KeychainSyncStore {
  KeychainSyncStore._();
  static final KeychainSyncStore instance = KeychainSyncStore._();

  static const _fileName = 'keychain_icloud_sync.txt';

  bool _cached = false;
  bool _value = false;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<bool> isEnabled() async {
    if (_cached) return _value;
    try {
      final f = await _file();
      if (await f.exists()) {
        _value = (await f.readAsString()).trim() == '1';
      }
    } catch (_) {}
    _cached = true;
    return _value;
  }

  Future<void> setEnabled(bool enabled) async {
    _value = enabled;
    _cached = true;
    final f = await _file();
    await f.writeAsString(enabled ? '1' : '0');
  }
}
