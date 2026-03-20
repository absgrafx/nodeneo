import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/chain_config.dart';
import 'rpc_settings_store.dart';

/// Pre-flight JSON-RPC checks before persisting a custom `ETH_RPC_URL` override.
class RpcEndpointValidator {
  RpcEndpointValidator._();

  static const _jsonRpcBody = '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}';
  static const _userAgent = 'RedPill-RPC-Check/1.0';

  /// Splits URLs the same way as Go's multi-RPC parser (comma / newline / etc.).
  static List<String> parseUrlList(String raw) {
    return raw
        .split(RegExp(r'[,\n;|]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns `null` if every URL responds with `eth_chainId` matching [expectedChainId].
  /// Otherwise a single user-facing error string (first failure).
  static Future<String?> validateUrls(
    String rawUrls, {
    int expectedChainId = defaultBaseChainId,
  }) async {
    final formatErr = RpcSettingsStore.validateUserInput(rawUrls);
    if (formatErr != null) return formatErr;

    final urls = parseUrlList(rawUrls);
    for (final url in urls) {
      final err = await _probeOne(url, expectedChainId);
      if (err != null) {
        return '${_shortUrl(url)} — $err';
      }
    }
    return null;
  }

  static String _shortUrl(String url) {
    if (url.length <= 56) return url;
    return '${url.substring(0, 40)}…';
  }

  static Future<String?> _probeOne(String url, int expectedChainId) async {
    late final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return 'invalid URL';
    }
    if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return 'URL must start with https:// or http://';
    }
    if (uri.host.isEmpty) return 'URL is missing a host';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    client.userAgent = _userAgent;

    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.write(_jsonRpcBody);
      final resp = await req.close().timeout(const Duration(seconds: 18));
      final text = await resp.transform(utf8.decoder).join();

      if (text.trimLeft().startsWith('<')) {
        return 'got HTML (not JSON-RPC) — often a WAF or wrong URL';
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return 'HTTP ${resp.statusCode}';
      }

      final dynamic map;
      try {
        map = jsonDecode(text);
      } catch (_) {
        return 'response is not valid JSON';
      }
      if (map is! Map) return 'unexpected JSON shape';
      if (map['error'] != null) {
        final e = map['error'];
        if (e is Map && e['message'] != null) {
          return 'RPC error: ${e['message']}';
        }
        return 'RPC error: $e';
      }
      final cid = map['result'];
      if (cid is! String) return 'missing eth_chainId in response';

      final hex = cid.trim().toLowerCase();
      if (!hex.startsWith('0x')) {
        return 'unexpected chainId format (expected 0x… hex)';
      }
      int chainFromResp;
      try {
        chainFromResp = int.parse(hex.substring(2), radix: 16);
      } catch (_) {
        return 'could not parse chainId $cid';
      }
      if (chainFromResp != expectedChainId) {
        return 'wrong chain: reported $chainFromResp (need $expectedChainId for Base mainnet)';
      }
      return null;
    } on SocketException catch (e) {
      return 'unreachable (${e.message})';
    } on TimeoutException {
      return 'timed out (no JSON-RPC response)';
    } on HandshakeException catch (e) {
      return 'TLS error: ${e.message}';
    } catch (e) {
      return e.toString();
    } finally {
      client.close(force: true);
    }
  }
}
