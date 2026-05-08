import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/bridge.dart';
import '../../services/form_factor.dart';
import '../../services/platform_caps.dart';
import '../../theme.dart';
import '../../widgets/section_card.dart';
import '../wallet/wallet_security_actions.dart';

/// Logger name used by [developer.log] — visible in Xcode / Console.app under
/// the bundle id even in release builds, unlike `debugPrint`. If a tap looks
/// like it does nothing, filter Console.app for `subsystem == com.absgrafx.nodeneo`
/// or grep for `[backup-reset]` in any log dump.
const String _logName = 'backup-reset';

/// Type group used for both Save and Open dialogs. We accept any extension
/// because real `.nnbak` files were unrecognised by the system on first
/// open (no UTType registered for our private extension), and tightening
/// the filter just hides the user's own backup. The extension list stays
/// here as a hint for the system picker and as documentation.
const XTypeGroup _backupTypeGroup = XTypeGroup(
  label: 'Node Neo backup',
  extensions: <String>['nnbak'],
);

/// Backup & Reset screen: data export/import and destructive operations.
class BackupResetScreen extends StatefulWidget {
  final Future<void> Function()? onWalletErased;
  final Future<void> Function()? onFactoryReset;

  const BackupResetScreen({
    super.key,
    this.onWalletErased,
    this.onFactoryReset,
  });

  @override
  State<BackupResetScreen> createState() => _BackupResetScreenState();
}

class _BackupResetScreenState extends State<BackupResetScreen> {
  bool _exporting = false;
  bool _importing = false;

  /// Pulls the wallet's private key (used as the backup passphrase) out of
  /// the Go bridge. Returns `null` if no wallet exists; **rethrows** any
  /// other exception so the caller can show it to the user. The previous
  /// implementation swallowed every error and treated all failures as
  /// "no wallet found", which made plugin / FFI failures invisible.
  String? _walletPassphrase() {
    final Map<String, dynamic> res;
    try {
      res = GoBridge().exportPrivateKey();
    } on GoBridgeException catch (e) {
      // "no wallet" is a known sentinel error from the Go side — fall
      // through and return null so the caller can show a clean message.
      // Anything else, rethrow so it surfaces in the outer catch.
      final msg = e.message.toLowerCase();
      if (msg.contains('no wallet') ||
          msg.contains('not found') ||
          msg.contains('not initialised') ||
          msg.contains('not initialized')) {
        return null;
      }
      rethrow;
    }
    final pk = res['private_key'] as String? ?? '';
    if (pk.isEmpty) return null;
    return pk;
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
    developer.log('export tap', name: _logName);
    if (_exporting) {
      _showError(
        'Export already in progress — wait for the previous attempt to '
        'finish or cancel its save dialog.',
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final String? passphrase;
      try {
        passphrase = _walletPassphrase();
      } catch (e, st) {
        developer.log(
          'wallet passphrase lookup threw',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        _showError('Could not read wallet to encrypt the backup: $e');
        return;
      }
      if (passphrase == null) {
        _showError('No wallet found — cannot export.');
        return;
      }

      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final fileName = 'nodeneo-backup-$ts.nnbak';

      final info = await PackageInfo.fromPlatform();
      developer.log(
        'export prepare: file=$fileName mobile=${PlatformCaps.isMobile} '
        'app=${info.version}+${info.buildNumber}',
        name: _logName,
      );

      if (PlatformCaps.isMobile) {
        // iOS/Android: write the encrypted backup to a temp file via the Go
        // bridge, then surface a Files-app save sheet
        // (UIDocumentPickerViewController) to let the user pick a final
        // destination. We do the bytes-to-final-location copy ourselves
        // because the picker only returns a sandbox-scoped path.
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = '${tmpDir.path}/$fileName';
        GoBridge().exportBackup(
          tmpPath,
          passphrase,
          info.version,
          _walletPrefix(),
        );
        final bytes = await File(tmpPath).readAsBytes();
        developer.log(
          'export staged: tmp=$tmpPath bytes=${bytes.length}',
          name: _logName,
        );
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
        );
        if (saveLocation == null) {
          developer.log('export cancelled by user (mobile)', name: _logName);
          return;
        }
        final fileData = XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType: 'application/octet-stream',
        );
        await fileData.saveTo(saveLocation.path);
        await File(tmpPath).delete().catchError((_) => File(tmpPath));
      } else {
        // Desktop: hand the system save panel a starting directory and let
        // the user pick the final path; the Go bridge writes directly to it.
        final dir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        developer.log(
          'export prompting save panel: initial=${dir.path}',
          name: _logName,
        );
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          initialDirectory: dir.path,
          acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
        );
        if (saveLocation == null) {
          developer.log('export cancelled by user (desktop)', name: _logName);
          return;
        }
        developer.log(
          'export writing: path=${saveLocation.path}',
          name: _logName,
        );
        GoBridge().exportBackup(
          saveLocation.path,
          passphrase,
          info.version,
          _walletPrefix(),
        );
      }

      developer.log('export ok: $fileName', name: _logName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to $fileName'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, st) {
      // Catch EVERYTHING (PlatformException from file_selector, MissingPluginException,
      // GoBridgeException, FileSystemException, ArgumentError, …) so the user
      // gets a real message instead of a silent no-op.
      developer.log(
        'export failed',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importBackup() async {
    developer.log('import tap', name: _logName);
    if (_importing) {
      _showError(
        'Import already in progress — wait for the current attempt to '
        'finish or cancel its file picker.',
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final String? passphrase;
      try {
        passphrase = _walletPassphrase();
      } catch (e, st) {
        developer.log(
          'wallet passphrase lookup threw',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        _showError('Could not read wallet to decrypt the backup: $e');
        return;
      }
      if (passphrase == null) {
        _showError('No wallet found — cannot decrypt backup.');
        return;
      }

      developer.log('import prompting open panel', name: _logName);
      final picked = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
        confirmButtonText: 'Import',
      );
      if (picked == null) {
        developer.log('import cancelled by user', name: _logName);
        return;
      }
      final inputPath = picked.path;
      if (inputPath.isEmpty) {
        developer.log('import picked empty path', name: _logName);
        _showError(
          'Selected file path was empty — try picking the .nnbak again.',
        );
        return;
      }
      if (!mounted) return;
      developer.log('import picked: $inputPath', name: _logName);

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
      if (ok != true || !mounted) {
        developer.log('import confirmation declined', name: _logName);
        return;
      }

      developer.log('import calling Go bridge', name: _logName);
      final manifest = GoBridge().importBackup(inputPath, passphrase);
      final convos = manifest['conversations'] ?? 0;
      final msgs = manifest['messages'] ?? 0;
      developer.log(
        'import ok: convos=$convos msgs=$msgs',
        name: _logName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $convos conversations, $msgs messages.'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, st) {
      developer.log(
        'import failed',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Show a user-visible error in a SnackBar with a long enough duration to
  /// actually read it. The default SnackBar dismisses after 4s which is too
  /// fast for multi-line plugin / FFI errors. Also no-ops cleanly when
  /// `mounted == false`, mirroring the rest of the file.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () =>
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  Future<void> _confirmFactoryReset() async {
    await showFactoryResetFlow(context, onFactoryReset: widget.onFactoryReset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Reset')),
      body: MaxContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionCard(
              icon: Icons.backup_outlined,
              title: 'Data Backup',
              child: Column(
                children: [
                  // NOTE: Always wire `onTap` to the handler — never to a
                  // gated `_exporting ? () {} : _handler` no-op. The handler
                  // itself checks the busy flag and shows an "already in
                  // progress" SnackBar; that way a stuck flag (e.g. from a
                  // platform-channel call that never resolved) surfaces as
                  // visible feedback instead of a silent dead button.
                  _SettingsCard(
                    icon: Icons.upload_file_outlined,
                    iconColor: NeoTheme.emerald,
                    title: 'Export Backup',
                    subtitle:
                        'Save conversations and settings to an encrypted file',
                    onTap: _exportBackup,
                    trailing: _exporting
                        ? const _BusySpinner()
                        : null,
                  ),
                  const Divider(height: 1, indent: 56),
                  _SettingsCard(
                    icon: Icons.download_outlined,
                    iconColor: NeoTheme.emerald,
                    title: 'Import Backup',
                    subtitle:
                        'Restore from a .nnbak file (replaces current data)',
                    onTap: _importBackup,
                    trailing: _importing
                        ? const _BusySpinner()
                        : null,
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
  final Widget? trailing;

  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    required this.onTap,
    this.trailing,
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
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: theme.hintColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny inline spinner shown next to a settings card when its async action is
/// in flight. Gives a visible cue that the tap is doing something even when
/// the underlying platform call is slow (e.g. a save / open panel that takes
/// a beat to present on macOS).
class _BusySpinner extends StatelessWidget {
  const _BusySpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}
