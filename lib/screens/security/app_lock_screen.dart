import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
import '../../theme.dart';
import 'app_lock_autofill.dart';

/// Full-screen unlock. Password field uses [AutofillHints.password] for iCloud Keychain /
/// 1Password / Google Password Manager.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _user = TextEditingController(text: kAppLockAutofillUsername);
  final _pw = TextEditingController();
  final _pwFocus = FocusNode();
  final _auth = LocalAuthentication();
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _unlockWithPassword() async {
    final p = _pw.text;
    if (p.isEmpty) {
      setState(() => _error = 'Enter your app password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLockService.instance.verifyPassword(p);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Do not prompt to "save" on unlock — only when setting/changing password.
      TextInput.finishAutofillContext(shouldSave: false);
      AppLockService.instance.markUnlocked();
    } else {
      setState(() => _error = 'Incorrect password.');
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (!await AppLockService.instance.biometricEnabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      if (!supported || !can) {
        if (mounted) setState(() => _error = 'Biometrics not available on this device.');
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock RedPill',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        AppLockService.instance.markUnlocked();
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Biometric authentication failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text('RedPill', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'App is locked',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 40),
                AppLockHiddenUsernameForAutofill(controller: _user),
                const SizedBox(height: 8),
                TextField(
                  controller: _pw,
                  focusNode: _pwFocus,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  keyboardType: TextInputType.visiblePassword,
                  onSubmitted: (_) => _unlockWithPassword(),
                  decoration: InputDecoration(
                    labelText: 'App password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _unlockWithPassword,
                  style: FilledButton.styleFrom(backgroundColor: RedPillTheme.green),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Unlock'),
                ),
                FutureBuilder<bool>(
                  future: AppLockService.instance.biometricEnabled,
                  builder: (context, snap) {
                    final bio = snap.data == true;
                    if (!bio) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _unlockWithBiometrics,
                        icon: const Icon(Icons.fingerprint, size: 22),
                        label: const Text('Use biometrics'),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Text(
                  'Your password manager can save and fill the app password (same as Security → Set app password).',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
