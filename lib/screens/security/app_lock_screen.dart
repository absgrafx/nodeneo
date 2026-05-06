import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../services/app_lock_service.dart';
import '../../services/biometric_labels.dart';
import '../../constants/app_brand.dart';
import '../../theme.dart';
import '../../widgets/app_lock_recovery_sheet.dart';
import '../../widgets/morpheus_logo.dart';
import '../wallet/wallet_security_actions.dart';
import 'app_lock_autofill.dart';

/// Full-screen unlock.
class AppLockScreen extends StatefulWidget {
  /// Clears wallet, lock, SQLite, RPC — returns app to onboarding (see [NodeNeoApp]).
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
  // Guard so a user-cancelled biometric prompt doesn't immediately re-fire
  // when the framework rebuilds (e.g. orientation, keyboard insets). One
  // auto-fire per mount; the manual button stays available for retries.
  bool _autoFiredBiometric = false;
  LockMode _mode = LockMode.passwordOnly;
  bool _modeLoaded = false;
  // In `passwordWithBiometric` mode the password field is collapsed by default
  // so the biometric option is the visually obvious primary path. The user can
  // expand it with "Use password instead" if biometrics fail / are unavailable.
  bool _passwordExpanded = false;
  // Best-guess biometric labels initialise from the platform. Refined on
  // initState by an async device probe (Face ID vs Touch ID, etc.).
  BiometricLabels _bio = BiometricLabels.platformGuess;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _refineBiometricLabels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoTriggerBiometric();
    });
  }

  Future<void> _loadMode() async {
    final m = await AppLockService.instance.mode;
    if (!mounted) return;
    setState(() {
      _mode = m;
      _modeLoaded = true;
    });
  }

  Future<void> _refineBiometricLabels() async {
    final labels = await BiometricLabels.probe(_auth);
    if (!mounted) return;
    setState(() => _bio = labels);
  }

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  /// Fire Face ID / Touch ID automatically when the lock screen mounts so
  /// biometrics are the primary unlock path on devices that support them.
  /// Cancellation falls through silently — the password field stays as a
  /// usable fallback without flashing an error.
  Future<void> _maybeAutoTriggerBiometric() async {
    if (!mounted || _autoFiredBiometric || _busy) return;
    if (!await AppLockService.instance.biometricEnabled) return;
    try {
      final supported = await _auth.isDeviceSupported();
      final can = supported && await _auth.canCheckBiometrics;
      if (!mounted || !can) return;
    } catch (_) {
      return;
    }
    _autoFiredBiometric = true;
    await _unlockWithBiometrics(silentOnCancel: true);
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
    final ok = await showFactoryResetFlow(context, onFactoryReset: null);
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

  Future<void> _unlockWithBiometrics({bool silentOnCancel = false}) async {
    if (!await AppLockService.instance.biometricEnabled) return;
    setState(() {
      _busy = true;
      if (!silentOnCancel) _error = null;
    });
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      if (!supported || !can) {
        if (mounted && !silentOnCancel) {
          setState(() => _error = 'Biometrics not available on this device.');
        }
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock ${AppBrand.displayName} with ${_bio.name}',
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
      if (mounted && !silentOnCancel) {
        setState(() => _error = e.message ?? 'Biometric authentication failed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // While we resolve the mode, show the most defensive layout (password +
    // biometric button) so the screen never flashes empty.
    final mode = _modeLoaded ? _mode : LockMode.passwordWithBiometric;
    final showBiometric = mode == LockMode.biometricOnly ||
        mode == LockMode.passwordWithBiometric;
    final hasPasswordFallback = mode == LockMode.passwordOnly ||
        mode == LockMode.passwordWithBiometric;
    // Steve-Jobs UX: when both Face ID and a password are configured, Face ID
    // is the only thing visible at first. The password field stays hidden
    // behind a "Use password instead" link so the screen reads as a single
    // primary CTA. Password-only users still see the field immediately.
    final showPasswordField = mode == LockMode.passwordOnly ||
        (mode == LockMode.passwordWithBiometric && _passwordExpanded);
    final showPasswordToggle = mode == LockMode.passwordWithBiometric &&
        !_passwordExpanded;

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
                      const NeoLogo(size: 192),
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
                if (showBiometric)
                  Padding(
                    padding: EdgeInsets.only(bottom: showPasswordField ? 20 : 0),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      style: FilledButton.styleFrom(
                        backgroundColor: NeoTheme.green,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.fingerprint, size: 22),
                      label: Text(_bio.unlockCta),
                    ),
                  ),
                if (showPasswordToggle)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _passwordExpanded = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _pwFocus.requestFocus();
                              });
                            },
                      child: Text(
                        'Use password instead',
                        style: TextStyle(color: theme.hintColor, fontSize: 13),
                      ),
                    ),
                  ),
                if (showPasswordField) ...[
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
                      fillColor: NeoTheme.mainPanelFill,
                      hintText: 'Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NeoTheme.mainPanelOutline(0.4)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NeoTheme.mainPanelOutline(0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NeoTheme.mainPanelOutline(0.85)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
                ],
                if (showPasswordField) ...[
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _busy ? null : _unlockWithPassword,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Unlock with password'),
                  ),
                  if (mode == LockMode.passwordWithBiometric)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _pw.clear();
                                _error = null;
                                _passwordExpanded = false;
                              }),
                      child: Text(
                        'Hide password',
                        style: TextStyle(color: theme.hintColor, fontSize: 12),
                      ),
                    ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          showAppLockRecoverySheet(context);
                        },
                  child: Text(
                    hasPasswordFallback
                        ? 'Forgot password? Recover with private key'
                        : 'Can\'t use ${_bio.name}? Recover with private key',
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                ),
                if (widget.onFullFactoryReset != null)
                  TextButton(
                    onPressed: _busy ? null : _confirmFullFactoryReset,
                    child: Text(
                      'Erase app data (factory reset)',
                      style: TextStyle(color: NeoTheme.red.withValues(alpha: 0.9), fontSize: 13),
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
