import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/chain_config.dart';
import '../../services/bridge.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../theme.dart';

/// Expert Mode screen: Network RPC + REST API.
///
/// Pops with `true` when RPC settings are saved/cleared so the caller can
/// restart the SDK.
class ExpertScreen extends StatefulWidget {
  const ExpertScreen({super.key});

  @override
  State<ExpertScreen> createState() => _ExpertScreenState();
}

class _ExpertScreenState extends State<ExpertScreen> {
  // ── Network state ───────────────────────────────────────────
  final _rpcCtrl = TextEditingController();
  bool _rpcLoading = true;
  bool _rpcSaving = false;
  bool _rpcTesting = false;
  String? _rpcOverridePreview;
  List<Map<String, dynamic>>? _rpcTestResults;
  bool _rpcChanged = false;

  // ── Expert API state ────────────────────────────────────────
  bool _apiRunning = false;
  String _apiRunningAddress = '';
  bool _apiNetworkAccessible = false;
  final _apiPortCtrl = TextEditingController(text: '8082');
  final _apiBaseUrlCtrl = TextEditingController();
  String _detectedIp = '';

  @override
  void initState() {
    super.initState();
    _loadRpc();
    _detectLocalIp();
    _refreshApiStatus();
  }

  @override
  void dispose() {
    _rpcCtrl.dispose();
    _apiPortCtrl.dispose();
    _apiBaseUrlCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  NETWORK
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadRpc() async {
    final o = await RpcSettingsStore.instance.readOverride();
    if (!mounted) return;
    setState(() {
      _rpcCtrl.text = o ?? '';
      _rpcOverridePreview = o;
      _rpcLoading = false;
    });
  }

  Future<void> _saveRpc() async {
    if (_rpcCtrl.text.trim().isEmpty) {
      await _useDefaultRpc();
      return;
    }
    final err = RpcSettingsStore.validateUserInput(_rpcCtrl.text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _rpcSaving = true);
    try {
      final probe = await RpcEndpointValidator.validateUrls(
        _rpcCtrl.text.trim(),
        expectedChainId: defaultBaseChainId,
      );
      if (!mounted) return;
      if (probe != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RPC check failed: $probe'),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
      await RpcSettingsStore.instance.writeOverride(_rpcCtrl.text.trim());
      if (!mounted) return;
      _rpcChanged = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Restarting connection...')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _rpcSaving = false);
    }
  }

  Future<void> _testRpc() async {
    final raw = _rpcCtrl.text.trim();
    final isDefaults = raw.isEmpty;
    final urlsToTest = isDefaults ? publicFallbackRpcUrls : raw;

    if (!isDefaults) {
      final err = RpcSettingsStore.validateUserInput(raw);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
    }
    setState(() {
      _rpcTesting = true;
      _rpcTestResults = null;
    });
    try {
      final results = await RpcEndpointValidator.validateAllUrls(
        urlsToTest,
        expectedChainId: defaultBaseChainId,
      );
      if (!mounted) return;

      if (isDefaults && hasBuildTimeRpc) {
        final dedicatedOk = await RpcEndpointValidator.anyReachable(
          defaultBaseMainnetRpcUrls,
          expectedChainId: defaultBaseChainId,
        );
        results.insert(0, {
          'url': '(bundled dedicated RPC)',
          'ok': dedicatedOk,
          'error': dedicatedOk ? null : 'unreachable or wrong chain',
        });
      }

      final okCount = results.where((r) => r['ok'] == true).length;
      setState(() => _rpcTestResults = results);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$okCount of ${results.length} RPC${results.length == 1 ? '' : 's'} passed (Base chainId $defaultBaseChainId)',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _rpcTesting = false);
    }
  }

  Future<void> _useDefaultRpc() async {
    setState(() => _rpcSaving = true);
    try {
      await RpcSettingsStore.instance.clearOverride();
      _rpcCtrl.clear();
      if (!mounted) return;
      _rpcChanged = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Using built-in public RPCs. Restarting...')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _rpcSaving = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  REST API
  // ═══════════════════════════════════════════════════════════════

  Future<void> _detectLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            _detectedIp = addr.address;
            _rebuildApiBaseUrl();
            return;
          }
        }
      }
    } catch (_) {}
    _detectedIp = '127.0.0.1';
    _rebuildApiBaseUrl();
  }

  void _rebuildApiBaseUrl() {
    if (_apiRunning) return;
    final host = _apiNetworkAccessible
        ? (_detectedIp.isNotEmpty ? _detectedIp : '127.0.0.1')
        : '127.0.0.1';
    final port = _apiPortCtrl.text.trim().isEmpty
        ? '8082'
        : _apiPortCtrl.text.trim();
    _apiBaseUrlCtrl.text = 'http://$host:$port';
    if (mounted) setState(() {});
  }

  void _refreshApiStatus() {
    try {
      final status = GoBridge().expertAPIStatus();
      final addr = status['address'] as String? ?? '';
      setState(() {
        _apiRunning = status['running'] as bool? ?? false;
        _apiRunningAddress = addr;
        if (addr.isNotEmpty) {
          _apiNetworkAccessible = addr.startsWith('0.0.0.0');
          final parts = addr.split(':');
          if (parts.length >= 2) {
            final p = int.tryParse(parts.last);
            if (p != null) _apiPortCtrl.text = p.toString();
          }
        }
      });
    } catch (_) {}
  }

  void _startApi() {
    try {
      final port = int.tryParse(_apiPortCtrl.text.trim()) ?? 8082;
      final listenHost = _apiNetworkAccessible ? '0.0.0.0' : '127.0.0.1';
      final addr = '$listenHost:$port';
      final publicURL = _apiBaseUrlCtrl.text.trim();
      GoBridge().startExpertAPI(addr, publicURL);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expert API started on $addr')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshApiStatus();
  }

  void _stopApi() {
    try {
      GoBridge().stopExpertAPI();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expert API stopped')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshApiStatus();
    _rebuildApiBaseUrl();
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _rpcChanged) {
          // Already handled via Navigator.pop(true) in save/clear methods.
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Expert Mode')),
        body: _rpcLoading
            ? const Center(
                child: CircularProgressIndicator(color: NeoTheme.green))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const _SectionBanner(title: 'Network'),
                  const SizedBox(height: 16),
                  _buildNetworkSection(theme),
                  const SizedBox(height: 32),
                  const _SectionBanner(title: 'REST API'),
                  const SizedBox(height: 16),
                  _buildApiSection(theme),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  // ── Network section ──────────────────────────────────────────

  Widget _buildNetworkSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _rpcOverridePreview != null && _rpcOverridePreview!.isNotEmpty
              ? 'Using a custom RPC override.'
              : 'Using built-in public RPC list.',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: NeoTheme.green.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rpcCtrl,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'Custom Base RPC (optional)',
            hintText: 'https://... or comma-separated',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasBuildTimeRpc
              ? 'A bundled dedicated RPC is available (not shown).'
              : 'Uses your node exclusively when set; otherwise falls back to public endpoints.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.hintColor, fontSize: 11),
        ),
        if (_rpcTestResults != null) ...[
          const SizedBox(height: 12),
          ..._rpcTestResults!.map((r) {
            final ok = r['ok'] == true;
            final url = r['url'] as String;
            final err = r['error'] as String?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ok
                      ? NeoTheme.green.withValues(alpha: 0.08)
                      : Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: ok
                        ? NeoTheme.green.withValues(alpha: 0.25)
                        : Colors.red.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      ok
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 18,
                      color: ok ? NeoTheme.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(url,
                              style: const TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                          if (err != null)
                            Text(err,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: (_rpcSaving || _rpcTesting) ? null : _testRpc,
              icon: _rpcTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(_rpcTesting ? 'Testing...' : 'Test',
                  style: const TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: (_rpcSaving || _rpcTesting) ? null : _saveRpc,
              style: FilledButton.styleFrom(
                backgroundColor: NeoTheme.green,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              ),
              child: _rpcSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: (_rpcSaving || _rpcTesting) ? null : _useDefaultRpc,
            child: Text(
              'Clear — use built-in public RPCs',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ),
        ),
      ],
    );
  }

  // ── REST API section ─────────────────────────────────────────

  Widget _buildApiSection(ThemeData theme) {
    final baseUrl = _apiBaseUrlCtrl.text.trim().isNotEmpty
        ? _apiBaseUrlCtrl.text.trim()
        : 'http://127.0.0.1:${_apiPortCtrl.text.trim().isEmpty ? '8082' : _apiPortCtrl.text.trim()}';
    final swaggerUrl = '$baseUrl/swagger/index.html';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start the full proxy-router HTTP server with Swagger documentation and all REST endpoints.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.hintColor, height: 1.35),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ScopeOption(
                icon: Icons.computer,
                label: 'Local only',
                selected: !_apiNetworkAccessible,
                enabled: !_apiRunning,
                onTap: () {
                  setState(() => _apiNetworkAccessible = false);
                  _rebuildApiBaseUrl();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ScopeOption(
                icon: Icons.wifi,
                label: 'Network',
                selected: _apiNetworkAccessible,
                enabled: !_apiRunning,
                onTap: () {
                  setState(() => _apiNetworkAccessible = true);
                  _rebuildApiBaseUrl();
                },
              ),
            ),
          ],
        ),
        if (_apiNetworkAccessible && !_apiRunning) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NeoTheme.amber.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: NeoTheme.amber.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16,
                    color: NeoTheme.amber.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Exposes API to all devices on your local network.',
                    style: TextStyle(
                        color: NeoTheme.amber.withValues(alpha: 0.9),
                        fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: _apiPortCtrl,
                enabled: !_apiRunning,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8082',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _rebuildApiBaseUrl(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _apiBaseUrlCtrl,
                enabled: !_apiRunning,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: _apiRunning
              ? FilledButton.icon(
                  onPressed: _stopApi,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Stop API Server', style: TextStyle(fontSize: 13)),
                )
              : FilledButton.icon(
                  onPressed: _startApi,
                  style: FilledButton.styleFrom(
                    backgroundColor: NeoTheme.green,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Start API Server', style: TextStyle(fontSize: 13)),
                ),
        ),
        if (_apiRunning)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: Text(
                'Listening on $_apiRunningAddress',
                style: TextStyle(
                    fontSize: 11,
                    color: NeoTheme.green.withValues(alpha: 0.9)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF374151)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  swaggerUrl,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    color: Color(0xFFD1D5DB),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy Swagger URL',
                icon: const Icon(Icons.copy_rounded, size: 16),
                style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(4),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: swaggerUrl));
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(const SnackBar(
                      content: Text('Swagger URL copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

}

// ── Full-width section banner ──────────────────────────────────

class _SectionBanner extends StatelessWidget {
  final String title;

  const _SectionBanner({required this.title});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 36,
      child: Transform.translate(
        offset: const Offset(-20, 0),
        child: OverflowBox(
          maxWidth: screenW,
          maxHeight: 36,
          alignment: Alignment.centerLeft,
          child: Container(
            width: screenW,
            color: NeoTheme.amber.withValues(alpha: 0.08),
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: NeoTheme.amber.withValues(alpha: 0.90),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable scope option for API section ─────────────────────

class _ScopeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? NeoTheme.green : const Color(0xFF6B7280);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? NeoTheme.green.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? NeoTheme.green.withValues(alpha: 0.5)
                : const Color(0xFF374151),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: enabled ? color : color.withValues(alpha: 0.4)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: enabled ? color : color.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

