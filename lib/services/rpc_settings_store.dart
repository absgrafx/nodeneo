import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config/chain_config.dart';

/// Optional user override for Base JSON-RPC URL(s). Stored on disk (not secret).
///
/// Empty / missing file → use [defaultBaseMainnetRpcUrls].
class RpcSettingsStore {
  RpcSettingsStore._();
  static final RpcSettingsStore instance = RpcSettingsStore._();

  static const _fileName = 'eth_rpc_override.txt';

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}nodeneo');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// Trims; returns `null` if unset or blank (use defaults).
  Future<String?> readOverride() async {
    final f = await _file();
    if (!await f.exists()) return null;
    final s = (await f.readAsString()).trim();
    return s.isEmpty ? null : s;
  }

  /// Persists override. Pass `null` or empty string to remove file (defaults).
  Future<void> writeOverride(String? urls) async {
    final f = await _file();
    final t = urls?.trim() ?? '';
    if (t.isEmpty) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.writeAsString(t, flush: true);
  }

  Future<void> clearOverride() => writeOverride(null);

  /// Value passed to Go `Init(ethNodeURL)`.
  Future<String> effectiveRpcUrl() async {
    final o = await readOverride();
    if (o != null && o.isNotEmpty) return o;
    return defaultBaseMainnetRpcUrls;
  }

  /// Basic sanity check before save (still may fail at SDK dial).
  static String? validateUserInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'Enter at least one https:// RPC URL, or clear the field to use defaults.';
    final chunks = s.split(RegExp(r'[,\n;|]+'));
    var any = false;
    for (final c in chunks) {
      final u = c.trim();
      if (u.isEmpty) continue;
      any = true;
      final lower = u.toLowerCase();
      if (!lower.startsWith('https://') && !lower.startsWith('http://')) {
        return 'Each URL must start with https:// or http://';
      }
    }
    if (!any) return 'Enter at least one RPC URL (not only commas or spaces).';
    return null;
  }
}
