import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/bridge.dart';

class LogSettingsScreen extends StatefulWidget {
  const LogSettingsScreen({super.key});

  @override
  State<LogSettingsScreen> createState() => _LogSettingsScreenState();
}

class _LogSettingsScreenState extends State<LogSettingsScreen> {
  String _level = 'info';
  String _logDir = '';
  List<_LogFileInfo> _logFiles = [];
  String _logTail = '';
  bool _loadingTail = false;
  final _tailScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final bridge = GoBridge();
      _level = bridge.getLogLevel();
      _logDir = bridge.getLogDir();
    } catch (_) {}
    _scanLogFiles();
    _loadLogTail();
    if (mounted) setState(() {});
  }

  Future<void> _loadLogTail() async {
    if (_logDir.isEmpty) return;
    final logFile = File('$_logDir/nodeneo.log');
    if (!logFile.existsSync()) {
      setState(() => _logTail = '(no log file yet)');
      return;
    }
    setState(() => _loadingTail = true);
    try {
      final lines = await logFile.readAsLines();
      final tail = lines.length <= 50 ? lines : lines.sublist(lines.length - 50);
      if (mounted) {
        setState(() {
          _logTail = tail.join('\n');
          _loadingTail = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_tailScrollCtrl.hasClients) {
            _tailScrollCtrl.jumpTo(_tailScrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logTail = '(error reading log: $e)';
          _loadingTail = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tailScrollCtrl.dispose();
    super.dispose();
  }

  void _scanLogFiles() {
    if (_logDir.isEmpty) return;
    final dir = Directory(_logDir);
    if (!dir.existsSync()) return;
    final entries = dir.listSync()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    _logFiles = entries
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .map((f) {
          final stat = f.statSync();
          return _LogFileInfo(
            name: f.uri.pathSegments.last,
            path: f.path,
            sizeKb: (stat.size / 1024).ceil(),
            modified: stat.modified,
          );
        })
        .toList();
  }

  void _setLevel(String level) {
    try {
      GoBridge().setLogLevel(level);
      setState(() => _level = level);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log level set to ${level.toUpperCase()}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Logs')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Log level',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Controls verbosity of the Go SDK logs written to disk. '
            'Debug is the most verbose; Error only records critical failures.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
          ),
          const SizedBox(height: 14),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Active level',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _level,
                items: const [
                  DropdownMenuItem(value: 'debug', child: Text('Debug')),
                  DropdownMenuItem(value: 'info', child: Text('Info (default)')),
                  DropdownMenuItem(value: 'warn', child: Text('Warning')),
                  DropdownMenuItem(value: 'error', child: Text('Error only')),
                ],
                onChanged: (v) {
                  if (v != null) _setLevel(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Log directory',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Logs rotate automatically: 10 MB per file, up to 5 rotated files.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
          ),
          const SizedBox(height: 12),
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
                    _logDir.isEmpty ? '—' : _logDir,
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
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
                  ),
                  onPressed: _logDir.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _logDir));
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text('Log path copied'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                        },
                ),
                if (Platform.isMacOS && _logDir.isNotEmpty)
                  IconButton(
                    tooltip: 'Open in Finder',
                    icon: const Icon(Icons.folder_open, size: 18),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: () => Process.run('open', [_logDir]),
                  ),
              ],
            ),
          ),
          if (_logFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Files',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final lf in _logFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lf.name,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: Color(0xFFD1D5DB),
                        ),
                      ),
                    ),
                    Text(
                      '${lf.sizeKb} KB',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent log output',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: _loadingTail
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                onPressed: _loadingTail ? null : _loadLogTail,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last 50 lines of nodeneo.log (live toggle — no restart needed).',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: _loadingTail
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Scrollbar(
                    controller: _tailScrollCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _tailScrollCtrl,
                      padding: const EdgeInsets.all(10),
                      child: SelectableText(
                        _logTail.isEmpty ? '(empty)' : _logTail,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: Color(0xFFD1D5DB),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogFileInfo {
  final String name;
  final String path;
  final int sizeKb;
  final DateTime modified;

  const _LogFileInfo({
    required this.name,
    required this.path,
    required this.sizeKb,
    required this.modified,
  });
}
