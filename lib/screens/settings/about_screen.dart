import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../constants/app_brand.dart';
import '../../services/bridge.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _appVersion = '';
  String _buildNumber = '';
  String _prVersion = 'unknown';
  bool _isFork = false;
  String _upstreamTag = '';
  int _forkCommits = 0;
  String _sdkCommit = '';

  String _logLevel = 'info';
  String _logDir = '';
  List<_LogFileInfo> _logFiles = [];
  String _logTail = '';
  bool _loadingTail = false;
  final _tailScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadLogs();
  }

  @override
  void dispose() {
    _tailScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    Map<String, dynamic>? prInfo;
    try {
      prInfo = GoBridge().getProxyRouterVersion();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
      _prVersion = prInfo?['version'] as String? ?? 'unknown';
      _isFork = prInfo?['is_fork'] as bool? ?? false;
      _upstreamTag = prInfo?['upstream_tag'] as String? ?? _prVersion;
      _forkCommits = prInfo?['fork_commits'] as int? ?? 0;
      _sdkCommit = prInfo?['commit'] as String? ?? '';
    });
  }

  void _loadLogs() {
    try {
      final bridge = GoBridge();
      _logLevel = bridge.getLogLevel();
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
      final tail =
          lines.length <= 50 ? lines : lines.sublist(lines.length - 50);
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

  void _scanLogFiles() {
    if (_logDir.isEmpty) return;
    final dir = Directory(_logDir);
    if (!dir.existsSync()) return;
    final entries = dir.listSync()
      ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
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
    }).toList();
  }

  void _setLogLevel(String level) {
    try {
      GoBridge().setLogLevel(level);
      setState(() => _logLevel = level);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log level set to ${level.toUpperCase()}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Version & Logs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            icon: Icons.info_outline_rounded,
            title: 'About',
            status: Text(
              'v$_appVersion',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: NeoTheme.platinum.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/branding/splash_logo.png',
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppBrand.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppBrand.tagline,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _VersionRow(label: 'App version', value: 'v$_appVersion ($_buildNumber)'),
                const SizedBox(height: 8),
                _VersionRow(
                  label: 'Proxy-router',
                  value: _isFork
                      ? '$_upstreamTag + $_forkCommits commits (fork)'
                      : _prVersion,
                ),
                if (_sdkCommit.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _VersionRow(
                    label: 'SDK commit',
                    value: _sdkCommit.length > 12 ? _sdkCommit.substring(0, 12) : _sdkCommit,
                    mono: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.article_outlined,
            title: 'Logs',
            status: StatusPill(
              active: _logLevel == 'debug',
              label: _logLevel[0].toUpperCase() + _logLevel.substring(1),
            ),
            child: _buildLoggingSection(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune, size: 18),
            const SizedBox(width: 10),
            Text('Log Level',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF374151)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _logLevel,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'debug', child: Text('Debug')),
                    DropdownMenuItem(value: 'info', child: Text('Info')),
                    DropdownMenuItem(value: 'warn', child: Text('Warning')),
                    DropdownMenuItem(
                        value: 'error', child: Text('Error only')),
                  ],
                  onChanged: (v) {
                    if (v != null) _setLogLevel(v);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_logDir.isNotEmpty) ...[
          InfoBox(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _logDir,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFFD1D5DB)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(32, 32),
                    padding: const EdgeInsets.all(4),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _logDir));
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(
                        content: Text('Log path copied'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ));
                  },
                ),
                if (Platform.isMacOS)
                  IconButton(
                    tooltip: 'Open in Finder',
                    icon: const Icon(Icons.folder_open, size: 16),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () => Process.run('open', [_logDir]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Logs rotate: 10 MB per file, up to 5 rotated files.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor, fontSize: 10),
          ),
        ],

        if (_logFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final lf in _logFiles)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 14, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(lf.name,
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Color(0xFFD1D5DB))),
                  ),
                  Text('${lf.sizeKb} KB',
                      style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 9,
                          color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
        ],

        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Recent output',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            IconButton(
              tooltip: 'Refresh logs',
              icon: _loadingTail
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              onPressed: _loadingTail ? null : _loadLogTail,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: _loadingTail
              ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Scrollbar(
                  controller: _tailScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _tailScrollCtrl,
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      _logTail.isEmpty ? '(empty)' : _logTail,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 9,
                        color: Color(0xFFD1D5DB),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}


class _VersionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _VersionRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: (mono
                    ? theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace')
                    : theme.textTheme.bodySmall)
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
