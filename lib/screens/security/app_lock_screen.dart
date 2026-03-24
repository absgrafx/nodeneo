import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
import '../../constants/app_brand.dart';
import '../../theme.dart';
import '../../widgets/app_lock_recovery_sheet.dart';
import '../../widgets/morpheus_logo.dart';
import 'app_lock_autofill.dart';

/// Full-screen unlock.
class AppLockScreen extends StatefulWidget {
  /// Clears wallet, lock, SQLite, RPC — returns app to onboarding (see [RedPillApp]).
  final Future<void> Function()? onFullFactoryReset;

  const AppLockScreen({super.key, this.onFullFactoryReset});

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
      TextInput.finishAutofillContext(shouldSave: false);
      AppLockService.instance.markUnlocked();
    } else {
      setState(() => _error = 'Incorrect password.');
    }
  }

  Future<void> _confirmFullFactoryReset() async {
    final go = widget.onFullFactoryReset;
    if (go == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory reset?'),
        content: const Text(
          'This removes the app lock, saved wallet, custom RPC URL, and all local chat history on this device. '
          'You will return to setup and must restore with your recovery phrase or private key.\n\n'
          'Your funds stay on-chain — nothing is moved. Only proceed if you have a backup.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: RedPillTheme.red),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await go();
    } finally {
      if (mounted) setState(() => _busy = false);
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
        localizedReason: 'Unlock ${AppBrand.displayName}',
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
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MorpheusLogo(size: 96, variant: MorpheusLogoVariant.green),
                      const SizedBox(height: 16),
                      Text(
                        AppBrand.displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
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
                    filled: true,
                    fillColor: RedPillTheme.mainPanelFill,
                    hintText: 'Password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: RedPillTheme.mainPanelOutline(0.4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: RedPillTheme.mainPanelOutline(0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: RedPillTheme.mainPanelOutline(0.85)),
                    ),
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
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          showAppLockRecoverySheet(context);
                        },
                  child: Text(
                    'Forgot password? Recover with phrase or key',
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                ),
                if (widget.onFullFactoryReset != null)
                  TextButton(
                    onPressed: _busy ? null : _confirmFullFactoryReset,
                    child: Text(
                      'Erase app data (factory reset)',
                      style: TextStyle(color: RedPillTheme.red.withValues(alpha: 0.9), fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
