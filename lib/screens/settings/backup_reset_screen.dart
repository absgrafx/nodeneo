import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/bridge.dart';
import '../../services/platform_caps.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';
import '../wallet/wallet_security_actions.dart';

/// Backup & Reset screen: data export/import and destructive operations.
class BackupResetScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;
  final Future<void> Function()? onFactoryReset;

  const BackupResetScreen({super.key, this.onWalletErased, this.onFactoryReset});

  @override
  State<BackupResetScreen> createState() => _BackupResetScreenState();
}

class _BackupResetScreenState extends State<BackupResetScreen> {
  bool _exporting = false;
  bool _importing = false;

  String? _walletPassphrase() {
    try {
      final res = GoBridge().exportPrivateKey();
      final pk = res['private_key'] as String? ?? '';
      if (pk.isNotEmpty) return pk;
    } catch (_) {}
    return null;
  }

  String _walletPrefix() {
    try {
      final info = GoBridge().getWalletSummary();
      var addr = (info['address'] as String? ?? '').toLowerCase();
      if (addr.startsWith('0x')) addr = addr.substring(2);
      return addr.length >= 8 ? addr.substring(0, 8) : addr;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _exportBackup() async {
    final passphrase = _walletPassphrase();
    if (passphrase == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No wallet found — cannot export.')),
        );
      }
      return;
    }

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final fileName = 'nodeneo-backup-$ts.nnbak';

    setState(() => _exporting = true);
    try {
      final info = await PackageInfo.fromPlatform();

      if (PlatformCaps.isMobile) {
        // iOS/Android: export to temp file, read bytes, pass to save dialog.
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = '${tmpDir.path}/$fileName';
        GoBridge().exportBackup(tmpPath, passphrase, info.version, _walletPrefix());
        final bytes = await File(tmpPath).readAsBytes();
        final outputPath = await FilePicker.saveFile(
          dialogTitle: 'Save backup',
          fileName: fileName,
          bytes: Uint8List.fromList(bytes),
        );
        await File(tmpPath).delete().catchError((_) => File(tmpPath));
        if (outputPath == null) return;
      } else {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final outputPath = await FilePicker.saveFile(
          dialogTitle: 'Save backup',
          fileName: fileName,
          initialDirectory: dir.path,
        );
        if (outputPath == null) return;
        GoBridge().exportBackup(outputPath, passphrase, info.version, _walletPrefix());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved to $fileName')),
        );
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importBackup() async {
    final passphrase = _walletPassphrase();
    if (passphrase == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No wallet found — cannot decrypt backup.')),
        );
      }
      return;
    }

    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select backup file',
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final inputPath = result.files.single.path;
    if (inputPath == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Backup?'),
        content: const Text(
          'This will replace ALL existing conversations, messages, and '
          'settings with the data from the backup file.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: NeoTheme.amber),
            child: const Text('Import & Replace'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _importing = true);
    try {
      final manifest = GoBridge().importBackup(inputPath, passphrase);
      if (mounted) {
        final convos = manifest['conversations'] ?? 0;
        final msgs = manifest['messages'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $convos conversations, $msgs messages.')),
        );
      }
    } on GoBridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.message}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmFactoryReset() async {
    await showFactoryResetFlow(
      context,
      onFactoryReset: widget.onFactoryReset,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Reset')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            icon: Icons.backup_outlined,
            title: 'Data Backup',
            child: Column(
              children: [
                _SettingsCard(
                  icon: Icons.upload_file_outlined,
                  iconColor: NeoTheme.emerald,
                  title: 'Export Backup',
                  subtitle: 'Save conversations and settings to an encrypted file',
                  onTap: _exporting ? () {} : _exportBackup,
                ),
                const Divider(height: 1, indent: 56),
                _SettingsCard(
                  icon: Icons.download_outlined,
                  iconColor: NeoTheme.emerald,
                  title: 'Import Backup',
                  subtitle: 'Restore from a .nnbak file (replaces current data)',
                  onTap: _importing ? () {} : _importBackup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.warning_amber_rounded,
            title: 'Danger Zone',
            accentColor: NeoTheme.red,
            child: Column(
              children: [
                _SettingsCard(
                  icon: Icons.delete_outline,
                  iconColor: NeoTheme.red.withValues(alpha: 0.9),
                  title: 'Erase Wallet on This Device',
                  titleColor: NeoTheme.red.withValues(alpha: 0.95),
                  subtitle:
                      'Removes saved phrase and conversations · on-chain funds unchanged',
                  onTap: () => showEraseWalletFlow(
                    context,
                    onWalletErased: widget.onWalletErased,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsCard(
                  icon: Icons.delete_forever_outlined,
                  iconColor: NeoTheme.red.withValues(alpha: 0.9),
                  title: 'Full Factory Reset',
                  titleColor: NeoTheme.red.withValues(alpha: 0.95),
                  subtitle:
                      'Erase ALL wallets, keys, databases, logs, and settings',
                  onTap: _confirmFactoryReset,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.hintColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
