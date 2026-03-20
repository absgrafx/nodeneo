import 'package:flutter/material.dart';

import '../../config/chain_config.dart';
import '../../services/rpc_settings_store.dart';
import '../../theme.dart';
import '../sessions/on_chain_sessions_screen.dart';

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
  String? _overridePreview;

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
          ? const Center(child: CircularProgressIndicator(color: RedPillTheme.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Custom RPC (optional)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  'Most users should stay on the built-in public Base endpoints. '
                  'Add your own only if you hit rate limits and have a URL you trust '
                  '(e.g. from your own node or a provider you pay). '
                  'RedPill does not use a central relay — traffic goes straight from this device to the RPC(s) you configure.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.4),
                ),
                const SizedBox(height: 20),
                Text(
                  _overridePreview != null && _overridePreview!.isNotEmpty
                      ? 'You are overriding defaults.'
                      : 'Using built-in public RPC list.',
                  style: theme.textTheme.labelSmall?.copyWith(color: RedPillTheme.green.withValues(alpha: 0.9)),
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
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
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
                  onPressed: _saving ? null : _useDefaults,
                  child: const Text('Clear — use built-in public RPCs'),
                ),
                const SizedBox(height: 28),
                Text('Sessions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'See inference sessions still open on-chain and close them to reclaim stake.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const OnChainSessionsScreen()),
                          );
                        },
                  icon: const Icon(Icons.hub_outlined, size: 20),
                  label: const Text('Open on-chain sessions'),
                ),
              ],
            ),
    );
  }
}
