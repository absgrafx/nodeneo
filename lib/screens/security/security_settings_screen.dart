import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
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
    if (!mounted) return;
    setState(() {
      _lockOn = lock;
      _bioOn = bio;
      _bioAvailable = can;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RedPillTheme.green))
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
                    style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
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
                    activeThumbColor: RedPillTheme.green,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _confirmDisableLock,
                    child: const Text('Turn off app lock', style: TextStyle(color: Color(0xFFF87171))),
                  ),
                ],
              ],
            ),
    );
  }
}
