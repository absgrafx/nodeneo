import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/bridge.dart';
import '../../theme.dart';

class ExpertModeScreen extends StatefulWidget {
  const ExpertModeScreen({super.key});

  @override
  State<ExpertModeScreen> createState() => _ExpertModeScreenState();
}

class _ExpertModeScreenState extends State<ExpertModeScreen> {
  bool _running = false;
  String _runningAddress = '';
  bool _networkAccessible = false;
  final _portCtrl = TextEditingController(text: '8082');
  final _baseUrlCtrl = TextEditingController();
  String _detectedIp = '';

  @override
  void initState() {
    super.initState();
    _detectLocalIp();
    _refreshStatus();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

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
            _rebuildBaseUrl();
            return;
          }
        }
      }
    } catch (_) {}
    _detectedIp = '127.0.0.1';
    _rebuildBaseUrl();
  }

  void _rebuildBaseUrl() {
    if (_running) return;
    final host = _networkAccessible
        ? (_detectedIp.isNotEmpty ? _detectedIp : '127.0.0.1')
        : '127.0.0.1';
    final port = _portCtrl.text.trim().isEmpty ? '8082' : _portCtrl.text.trim();
    _baseUrlCtrl.text = 'http://$host:$port';
    if (mounted) setState(() {});
  }

  void _refreshStatus() {
    try {
      final status = GoBridge().expertAPIStatus();
      final addr = status['address'] as String? ?? '';
      setState(() {
        _running = status['running'] as bool? ?? false;
        _runningAddress = addr;
        if (addr.isNotEmpty) {
          _networkAccessible = addr.startsWith('0.0.0.0');
          final parts = addr.split(':');
          if (parts.length >= 2) {
            final p = int.tryParse(parts.last);
            if (p != null) {
              _portCtrl.text = p.toString();
            }
          }
        }
      });
    } catch (_) {}
  }

  void _start() {
    try {
      final port = int.tryParse(_portCtrl.text.trim()) ?? 8082;
      final listenHost = _networkAccessible ? '0.0.0.0' : '127.0.0.1';
      final addr = '$listenHost:$port';
      final publicURL = _baseUrlCtrl.text.trim();
      GoBridge().startExpertAPI(addr, publicURL);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expert API started on $addr')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
    _refreshStatus();
  }

  void _stop() {
    try {
      GoBridge().stopExpertAPI();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expert API stopped')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
    _refreshStatus();
    _rebuildBaseUrl();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = _baseUrlCtrl.text.trim().isNotEmpty
        ? _baseUrlCtrl.text.trim()
        : 'http://127.0.0.1:${_portCtrl.text.trim().isEmpty ? '8082' : _portCtrl.text.trim()}';
    final swaggerUrl = '$baseUrl/swagger/index.html';

    return Scaffold(
      appBar: AppBar(title: const Text('Expert Mode')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Native Proxy-Router API',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Starts the full proxy-router HTTP server with Swagger documentation '
            'and all REST endpoints — the same API surface as a standalone '
            'proxy-router daemon.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
          ),

          const SizedBox(height: 24),

          // --- 1. Scope ---
          Text('Scope', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _ScopeSelector(
            networkAccessible: _networkAccessible,
            enabled: !_running,
            onChanged: (v) {
              setState(() => _networkAccessible = v);
              _rebuildBaseUrl();
            },
          ),
          if (_networkAccessible && !_running) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NeoTheme.amber.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: NeoTheme.amber.withValues(alpha: 0.8)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Network mode exposes the API to all devices on your local '
                      'network. Ensure your network is trusted.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NeoTheme.amber.withValues(alpha: 0.9),
                        height: 1.35,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // --- 2. Port ---
          Text('Port', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _portCtrl,
            enabled: !_running,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '8082',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _rebuildBaseUrl(),
          ),

          const SizedBox(height: 20),

          // --- 3. Base URL (for swagger CORS) ---
          Text('Base URL', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'The public URL that Swagger uses for "Try it out" requests. '
            'Auto-detected from your network — change it if you use a '
            'custom domain or reverse proxy.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35, fontSize: 11),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlCtrl,
            enabled: !_running,
            decoration: InputDecoration(
              hintText: 'http://192.168.1.42:8082',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: !_running
                  ? IconButton(
                      tooltip: 'Reset to detected IP',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _rebuildBaseUrl,
                    )
                  : null,
            ),
            style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
          ),

          const SizedBox(height: 28),

          // --- 4. Action ---
          if (_running)
            FilledButton.icon(
              onPressed: _stop,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                minimumSize: const Size(double.infinity, 48),
              ),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop API Server'),
            )
          else
            FilledButton.icon(
              onPressed: _start,
              style: FilledButton.styleFrom(
                backgroundColor: NeoTheme.green,
                minimumSize: const Size(double.infinity, 48),
              ),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Start API Server'),
            ),
          if (_running) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Listening on $_runningAddress',
                style: TextStyle(
                  fontSize: 11,
                  color: NeoTheme.green.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],

          const SizedBox(height: 6),
          Center(
            child: Text(
              _running
                  ? 'Stop the server to change scope, port, or base URL.'
                  : 'Configure scope, port, and base URL above, then start.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 11,
              ),
            ),
          ),

          const Divider(height: 36),

          // --- Swagger UI section ---
          Text(
            'Swagger UI',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    swaggerUrl,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      color: Color(0xFFF9FAFB),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Copy URL',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
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
          const SizedBox(height: 10),
          Text(
            'Open the Swagger URL in your browser to explore and test all '
            'proxy-router API endpoints interactively.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
          ),

          const SizedBox(height: 20),
          Text(
            'Key endpoint groups',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const _InfoRow(label: '/blockchain/*', desc: 'Balances, sessions, models, bids, transactions'),
          const _InfoRow(label: '/v1/chat/completions', desc: 'OpenAI-compatible chat API'),
          const _InfoRow(label: '/v1/models', desc: 'Available models'),
          const _InfoRow(label: '/wallet', desc: 'Wallet info & keys'),
          const _InfoRow(label: '/healthcheck', desc: 'System health'),
          const _InfoRow(label: '/proxy/*', desc: 'Provider sessions, chat, audio, IPFS'),
          const SizedBox(height: 12),
          Text(
            'Full API documentation is in the Swagger UI.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Scope selector: local vs network ---

class _ScopeSelector extends StatelessWidget {
  final bool networkAccessible;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ScopeSelector({
    required this.networkAccessible,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ScopeOption(
            icon: Icons.computer,
            label: 'This machine only',
            selected: !networkAccessible,
            enabled: enabled,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ScopeOption(
            icon: Icons.wifi,
            label: 'Network accessible',
            selected: networkAccessible,
            enabled: enabled,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
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
        child: Column(
          children: [
            Icon(icon, size: 22, color: enabled ? color : color.withValues(alpha: 0.4)),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String desc;

  const _InfoRow({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: Color(0xFFD1D5DB),
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
