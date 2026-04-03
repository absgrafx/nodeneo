import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
import '../../services/keychain_sync_store.dart';
import '../../services/wallet_vault.dart';
import '../../theme.dart';
import 'app_lock_autofill.dart';
import 'app_lock_setup_screen.dart';

/// App lock, biometrics, and related controls.
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _loading = true;
  bool _lockOn = false;
  bool _bioOn = false;
  bool _bioAvailable = false;
  bool _icloudSync = false;
  bool _icloudSyncChanging = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final auth = LocalAuthentication();
    final dev = await auth.isDeviceSupported();
    final can = dev && await auth.canCheckBiometrics;
    final lock = await AppLockService.instance.isLockEnabled;
    final bio = await AppLockService.instance.biometricEnabled;
    final sync = await KeychainSyncStore.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _lockOn = lock;
      _bioOn = bio;
      _bioAvailable = can;
      _icloudSync = sync;
      _loading = false;
    });
  }

  Future<void> _openEnableLock() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AppLockSetupScreen(changingPassword: false)),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _openChangePassword() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AppLockSetupScreen(changingPassword: true)),
    );
    if (ok == true && mounted) await _reload();
  }

  Future<void> _confirmDisableLock() async {
    final ctrl = TextEditingController();
    final userCtrl = TextEditingController(text: kAppLockAutofillUsername);
    final pwFocus = FocusNode();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off app lock?'),
        content: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Enter your app password to confirm.'),
              const SizedBox(height: 12),
              AppLockHiddenUsernameForAutofill(controller: userCtrl),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                focusNode: pwFocus,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  labelText: 'App password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final v = await AppLockService.instance.verifyPassword(ctrl.text);
              if (!ctx.mounted) return;
              if (v) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Incorrect password.')),
                );
              }
            },
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    userCtrl.dispose();
    pwFocus.dispose();
    if (ok == true) {
      await AppLockService.instance.disableLock();
      if (mounted) await _reload();
    }
  }

  Future<void> _setBiometric(bool v) async {
    if (v && !_bioAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometrics are not available on this device.')),
      );
      return;
    }
    await AppLockService.instance.setBiometricEnabled(v);
    if (mounted) await _reload();
  }

  Future<void> _setICloudSync(bool v) async {
    setState(() => _icloudSyncChanging = true);
    await KeychainSyncStore.instance.setEnabled(v);
    try {
      await WalletVault.instance.resyncKeychainItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Keychain update error: $e')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _icloudSync = v;
        _icloudSyncChanging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NeoTheme.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('App lock', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Adds a password (and optional Face ID / Touch ID) before using the wallet. '
                  'This is not your seed phrase — use a unique app password and store it in a password manager.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                ),
                const SizedBox(height: 20),
                if (!_lockOn)
                  FilledButton.icon(
                    onPressed: _openEnableLock,
                    style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                    icon: const Icon(Icons.lock_outline, size: 22),
                    label: const Text('Turn on app lock'),
                  )
                else ...[
                  OutlinedButton(
                    onPressed: _openChangePassword,
                    child: const Text('Change app password'),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unlock with biometrics'),
                    subtitle: Text(
                      _bioAvailable
                          ? 'Face ID, Touch ID, or fingerprint when supported.'
                          : 'Not available on this device.',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    value: _bioOn,
                    onChanged: (!_bioAvailable && !_bioOn) ? null : (v) => _setBiometric(v),
                    activeThumbColor: NeoTheme.green,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _confirmDisableLock,
                    child: const Text('Turn off app lock', style: TextStyle(color: Color(0xFFF87171))),
                  ),
                ],

                if (Platform.isMacOS || Platform.isIOS) ...[
                  const SizedBox(height: 32),
                  Divider(color: theme.dividerColor.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'iCloud Keychain',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When enabled, your wallet secret is stored in iCloud Keychain and syncs across your Apple devices '
                    'signed into the same Apple ID. Convenient for multi-device access, but means '
                    'your secret leaves this device.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sync wallet to iCloud Keychain'),
                    subtitle: Text(
                      _icloudSync
                          ? 'Your recovery phrase / private key will sync across devices.'
                          : 'Wallet secret stays on this device only.',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    value: _icloudSync,
                    onChanged: _icloudSyncChanging ? null : (v) => _setICloudSync(v),
                    activeThumbColor: NeoTheme.green,
                  ),
                  if (_icloudSync)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NeoTheme.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: NeoTheme.amber.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: NeoTheme.amber.withValues(alpha: 0.9)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Anyone with access to your Apple ID can read the synced wallet secret. '
                                'Keep your Apple ID credentials and two-factor authentication secure.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: NeoTheme.amber.withValues(alpha: 0.85),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
