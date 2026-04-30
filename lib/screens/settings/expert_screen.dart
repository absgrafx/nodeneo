import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/chain_config.dart';
import '../../services/bridge.dart';
import '../../services/form_factor.dart';
import '../../services/platform_caps.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';

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
  String _apiCredUser = '';
  String _apiCredPass = '';
  bool _apiCredRevealed = false;

  // ── Gateway state ─────────────────────────────────────────
  bool _gwRunning = false;
  String _gwAddress = '';
  bool _gwNetworkAccessible = false;
  final _gwPortCtrl = TextEditingController(text: '8083');
  List<Map<String, dynamic>> _apiKeys = [];
  String? _newKeyFull; // shown once after generation

  @override
  void initState() {
    super.initState();
    _loadRpc();
    if (PlatformCaps.supportsDeveloperApi) {
      _detectLocalIp();
      _refreshApiStatus();
      _loadApiCredentials();
    }
    if (PlatformCaps.supportsGateway) {
      _refreshGatewayStatus();
      _loadApiKeys();
    }
  }

  @override
  void dispose() {
    _rpcCtrl.dispose();
    _apiPortCtrl.dispose();
    _apiBaseUrlCtrl.dispose();
    _gwPortCtrl.dispose();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err)));
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
          content: Text('Using built-in public RPCs. Restarting...'),
        ),
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

  void _loadApiCredentials() {
    try {
      final creds = GoBridge().getExpertAPICredentials();
      setState(() {
        _apiCredUser = creds['username'] as String? ?? '';
        _apiCredPass = creds['password'] as String? ?? '';
      });
    } catch (_) {}
  }

  void _resetApiPassword() {
    try {
      final creds = GoBridge().resetExpertAPIPassword();
      setState(() {
        _apiCredUser = creds['username'] as String? ?? '';
        _apiCredPass = creds['password'] as String? ?? '';
        _apiCredRevealed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset. Takes effect on next API start.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Expert API started on $addr')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshApiStatus();
    _loadApiCredentials();
  }

  void _stopApi() {
    try {
      GoBridge().stopExpertAPI();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expert API stopped')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshApiStatus();
    _rebuildApiBaseUrl();
  }

  // ═══════════════════════════════════════════════════════════════
  //  GATEWAY
  // ═══════════════════════════════════════════════════════════════

  void _refreshGatewayStatus() {
    try {
      final status = GoBridge().gatewayStatus();
      final addr = status['address'] as String? ?? '';
      setState(() {
        _gwRunning = status['running'] as bool? ?? false;
        _gwAddress = addr;
        if (addr.isNotEmpty) {
          _gwNetworkAccessible = addr.startsWith('0.0.0.0');
          final parts = addr.split(':');
          if (parts.length >= 2) {
            final p = int.tryParse(parts.last);
            if (p != null) _gwPortCtrl.text = p.toString();
          }
        }
      });
    } catch (_) {}
  }

  void _startGateway() {
    try {
      final port = int.tryParse(_gwPortCtrl.text.trim()) ?? 8083;
      final host = _gwNetworkAccessible ? '0.0.0.0' : '127.0.0.1';
      final addr = '$host:$port';
      GoBridge().startGateway(addr);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gateway started on $addr')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshGatewayStatus();
  }

  void _stopGateway() {
    try {
      GoBridge().stopGateway();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gateway stopped')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _refreshGatewayStatus();
  }

  void _loadApiKeys() {
    try {
      final keys = GoBridge().listAPIKeys();
      setState(() {
        _apiKeys = keys.cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  void _generateApiKey() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate API Key'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Key name (optional)',
            hintText: 'e.g. Cursor, LangChain',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doGenerateKey(nameCtrl.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _doGenerateKey(String name) {
    try {
      final result = GoBridge().generateAPIKey(name);
      final fullKey = result['key'] as String? ?? '';
      setState(() => _newKeyFull = fullKey);
      _loadApiKeys();
      _showNewKeyDialog(fullKey);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showNewKeyDialog(String key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Key Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy this key now. It will not be shown again.',
              style: TextStyle(fontSize: 13, color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF374151)),
              ),
              child: SelectableText(
                key,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              ScaffoldMessenger.of(ctx)
                ..clearSnackBars()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Key copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy & Close'),
          ),
        ],
      ),
    );
  }

  void _revokeApiKey(String id, String prefix) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke API Key'),
        content: Text(
          'Revoke key $prefix...? This will immediately block any app using this key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              try {
                GoBridge().revokeAPIKey(id);
                _loadApiKeys();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Key revoked')));
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCustomRpc =
        _rpcOverridePreview != null && _rpcOverridePreview!.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _rpcChanged) {
          // Already handled via Navigator.pop(true) in save/clear methods.
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(PlatformCaps.isMobile ? 'Network' : 'Expert Mode'),
        ),
        body: _rpcLoading
            ? const Center(
                child: CircularProgressIndicator(color: NeoTheme.green),
              )
            : MaxContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    SectionCard(
                      icon: Icons.link_rounded,
                      title: 'Blockchain Connection',
                      status: StatusPill(
                        active: hasCustomRpc,
                        label: hasCustomRpc ? 'Custom' : 'Default',
                      ),
                      child: _buildNetworkSection(theme),
                    ),
                    if (PlatformCaps.supportsDeveloperApi) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        icon: Icons.code_rounded,
                        title: 'Developer API',
                        status: StatusPill(
                          active: _apiRunning,
                          label: _apiRunning
                              ? 'Running :${_apiPortCtrl.text}'
                              : 'Stopped',
                        ),
                        child: _buildApiSection(theme),
                      ),
                    ],
                    if (PlatformCaps.supportsGateway) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        icon: Icons.smart_toy_outlined,
                        title: 'AI Gateway',
                        status: StatusPill(
                          active: _gwRunning,
                          label: _gwRunning
                              ? 'Running :${_gwPortCtrl.text}'
                              : 'Stopped',
                        ),
                        child: _buildGatewaySection(theme),
                      ),
                    ],
                  ],
                ),
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
          'Node Neo needs an RPC endpoint to interact with the Base blockchain '
          '(opening sessions, checking balances, signing transactions). '
          'We provide a default — only change this if you experience connection issues '
          'or want to use your own node.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            height: 1.35,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _rpcOverridePreview != null && _rpcOverridePreview!.isNotEmpty
              ? 'Currently using a custom RPC.'
              : hasBuildTimeRpc
              ? 'Currently using the bundled default.'
              : 'Currently using built-in public endpoints.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: NeoTheme.green.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _rpcCtrl,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'Custom RPC endpoint (optional)',
            hintText: 'https://... or comma-separated',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                      ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 18,
                      color: ok ? NeoTheme.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            url,
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (err != null)
                            Text(
                              err,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            ),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(
                _rpcTesting ? 'Testing...' : 'Test',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: (_rpcSaving || _rpcTesting) ? null : _saveRpc,
              style: FilledButton.styleFrom(
                backgroundColor: NeoTheme.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 10,
                ),
              ),
              child: _rpcSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
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
          'Starts a local HTTP server with full Swagger documentation for '
          'developers and debugging. Exposes blockchain operations, session '
          'management, and low-level SDK functions.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            height: 1.35,
          ),
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
              border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: NeoTheme.amber.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Exposes API to all devices on your local network.',
                    style: TextStyle(
                      color: NeoTheme.amber.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
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
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text(
                    'Stop API Server',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              : FilledButton.icon(
                  onPressed: _startApi,
                  style: FilledButton.styleFrom(
                    backgroundColor: NeoTheme.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text(
                    'Start API Server',
                    style: TextStyle(fontSize: 13),
                  ),
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
                  color: NeoTheme.green.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        InfoBox(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(swaggerUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    swaggerUrl,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      color: Color(0xFFD1D5DB),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF6B7280),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Swagger URL copied'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_apiCredPass.isNotEmpty) ...[
          Text(
            'HTTP Basic Auth',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 4),
                    const Text(
                      'Username',
                      style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                    ),
                    const Spacer(),
                    Text(
                      _apiCredUser,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: Color(0xFFD1D5DB),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _copyIcon(context, _apiCredUser, 'Username copied'),
                  ],
                ),
                const Divider(height: 16, color: Color(0xFF374151)),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    const Text(
                      'Password',
                      style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                    ),
                    const Spacer(),
                    Text(
                      _apiCredRevealed
                          ? _apiCredPass
                          : '•' * _apiCredPass.length,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: _apiCredRevealed
                            ? const Color(0xFFD1D5DB)
                            : const Color(0xFF6B7280),
                        letterSpacing: _apiCredRevealed ? 0 : 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: _apiCredRevealed ? 'Hide' : 'Reveal',
                      icon: Icon(
                        _apiCredRevealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () =>
                          setState(() => _apiCredRevealed = !_apiCredRevealed),
                    ),
                    _copyIcon(context, _apiCredPass, 'Password copied'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Click Authorize in Swagger to enter these credentials.',
                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                ),
              ),
              TextButton(
                onPressed: _resetApiPassword,
                child: const Text(
                  'Reset password',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Credentials will be generated when you start the API.',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ],
      ],
    );
  }

  Widget _copyIcon(BuildContext context, String text, String snackMessage) {
    return IconButton(
      tooltip: 'Copy',
      icon: const Icon(Icons.copy_rounded, size: 14),
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 28),
        padding: EdgeInsets.zero,
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(snackMessage),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      },
    );
  }

  // ── Gateway section ──────────────────────────────────────────

  Widget _buildGatewaySection(ThemeData theme) {
    final host = _gwNetworkAccessible
        ? (_detectedIp.isNotEmpty ? _detectedIp : '127.0.0.1')
        : '127.0.0.1';
    final port = _gwPortCtrl.text.trim().isEmpty
        ? '8083'
        : _gwPortCtrl.text.trim();
    final gatewayBaseUrl = 'http://$host:$port/v1';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect external AI tools to Morpheus. Works with Cursor, LangChain, '
          'Claude Desktop, and any app that supports the OpenAI API format. '
          'Sessions and model selection are handled automatically.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ScopeOption(
                icon: Icons.computer,
                label: 'Local only',
                selected: !_gwNetworkAccessible,
                enabled: !_gwRunning,
                onTap: () => setState(() => _gwNetworkAccessible = false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ScopeOption(
                icon: Icons.wifi,
                label: 'Network',
                selected: _gwNetworkAccessible,
                enabled: !_gwRunning,
                onTap: () => setState(() => _gwNetworkAccessible = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 100,
          child: TextField(
            controller: _gwPortCtrl,
            enabled: !_gwRunning,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '8083',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: _gwRunning
              ? FilledButton.icon(
                  onPressed: _stopGateway,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text(
                    'Stop Gateway',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              : FilledButton.icon(
                  onPressed: _startGateway,
                  style: FilledButton.styleFrom(
                    backgroundColor: NeoTheme.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text(
                    'Start Gateway',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
        ),
        if (_gwRunning)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: Text(
                'Listening on $_gwAddress',
                style: TextStyle(
                  fontSize: 11,
                  color: NeoTheme.green.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),

        const SizedBox(height: 16),
        InfoBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.terminal_rounded,
                    size: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Cursor / OpenAI Config',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy base URL',
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(28, 28),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: gatewayBaseUrl));
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Base URL copied'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Base URL:  $gatewayBaseUrl',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: Color(0xFFD1D5DB),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'API Key:   sk-... (generate below)',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            ],
          ),
        ),

        // ── API Keys ───────────────────────────────────
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              'API Keys',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _generateApiKey,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Generate Key', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_apiKeys.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Text(
              'No API keys yet. Generate one to allow external apps to connect.',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...List.generate(_apiKeys.length, (i) {
            final k = _apiKeys[i];
            final prefix = k['prefix'] as String? ?? '';
            final name = k['name'] as String? ?? '';
            final id = k['id'] as String? ?? '';
            final lastUsed = k['last_used'] as int? ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.key_rounded,
                      size: 16,
                      color: Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$prefix...',
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 11,
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          if (name.isNotEmpty)
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.hintColor,
                              ),
                            ),
                          if (lastUsed > 0)
                            Text(
                              'Last used: ${DateTime.fromMillisecondsSinceEpoch(lastUsed * 1000).toLocal().toString().substring(0, 16)}',
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Revoke key',
                      icon: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Colors.red.shade400,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        padding: const EdgeInsets.all(4),
                      ),
                      onPressed: () => _revokeApiKey(id, prefix),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
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
            Icon(
              icon,
              size: 18,
              color: enabled ? color : color.withValues(alpha: 0.4),
            ),
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
