import 'package:flutter/material.dart';

import '../../config/chain_config.dart';
import '../../services/rpc_endpoint_validator.dart';
import '../../services/rpc_settings_store.dart';
import '../../constants/app_brand.dart';
import '../../theme.dart';

/// Advanced: user-supplied Base JSON-RPC URL(s). No central relay — same comma
/// rules as built-in defaults (see Go `parseEthNodeURLs`).
class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _overridePreview;
  List<Map<String, dynamic>>? _testResults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final o = await RpcSettingsStore.instance.readOverride();
    if (!mounted) return;
    setState(() {
      _ctrl.text = o ?? '';
      _overridePreview = o;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) {
      await _useDefaults();
      return;
    }
    final err = RpcSettingsStore.validateUserInput(_ctrl.text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    try {
      final probe = await RpcEndpointValidator.validateUrls(
        _ctrl.text.trim(),
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
      await RpcSettingsStore.instance.writeOverride(_ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Restarting connection…')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Validate reachability + Base chain ID without saving.
  /// When the field is empty, tests the built-in defaults.
  /// Tests ALL URLs and shows per-URL results.
  Future<void> _testOnly() async {
    final raw = _ctrl.text.trim();
    final urlsToTest = raw.isEmpty ? defaultBaseMainnetRpcUrls : raw;
    final isDefaults = raw.isEmpty;

    if (!isDefaults) {
      final err = RpcSettingsStore.validateUserInput(raw);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
    }
    setState(() {
      _testing = true;
      _testResults = null;
    });
    try {
      final results = await RpcEndpointValidator.validateAllUrls(
        urlsToTest,
        expectedChainId: defaultBaseChainId,
      );
      if (!mounted) return;
      final okCount = results.where((r) => r['ok'] == true).length;
      setState(() => _testResults = results);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$okCount of ${results.length} RPC${results.length == 1 ? '' : 's'} passed (Base chainId $defaultBaseChainId)'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _useDefaults() async {
    setState(() => _saving = true);
    try {
      await RpcSettingsStore.instance.clearOverride();
      _ctrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Using built-in public RPCs. Restarting…')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NeoTheme.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Custom RPC (optional)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  'Most users should stay on the built-in public Base endpoints. '
                  'Add your own only if you hit rate limits and have a URL you trust '
                  '(e.g. from your own node or a provider you pay). '
                  '${AppBrand.displayName} does not use a central relay — traffic goes straight from this device to the RPC(s) you configure.\n\n'
                  'Before saving, each URL is checked with a live JSON-RPC call (eth_chainId must be Base mainnet, $defaultBaseChainId). '
                  'Use Test URLs to verify without switching the app off the current RPC.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.4),
                ),
                const SizedBox(height: 20),
                Text(
                  _overridePreview != null && _overridePreview!.isNotEmpty
                      ? 'You are overriding defaults.'
                      : 'Using built-in public RPC list.',
                  style: theme.textTheme.labelSmall?.copyWith(color: NeoTheme.green.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  maxLines: 5,
                  style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'ETH_RPC_URL (Base mainnet)',
                    hintText: 'https://… or several separated by comma / newline',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Built-in default (first URL): ${defaultBaseMainnetRpcUrls.split(',').first}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: (_saving || _testing) ? null : _testOnly,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 20),
                  label: Text(_testing
                      ? 'Testing…'
                      : _ctrl.text.trim().isEmpty
                          ? 'Test built-in RPCs'
                          : 'Test URLs (no save)'),
                ),
                if (_testResults != null) ...[
                  const SizedBox(height: 16),
                  ..._testResults!.map((r) {
                    final ok = r['ok'] == true;
                    final url = r['url'] as String;
                    final err = r['error'] as String?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: (_saving || _testing) ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save & reconnect'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: (_saving || _testing) ? null : _useDefaults,
                  child: const Text('Clear — use built-in public RPCs'),
                ),
              ],
            ),
    );
  }
}
