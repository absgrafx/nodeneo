import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_lock_service.dart';
import '../../theme.dart';
import 'app_lock_autofill.dart';

/// Create or change app password. Uses [AutofillHints.newPassword] / [AutofillHints.password]
/// so iCloud Keychain, 1Password, Google Password Manager, etc. can save and fill.
class AppLockSetupScreen extends StatefulWidget {
  /// When true, require current password before setting a new one.
  final bool changingPassword;

  const AppLockSetupScreen({super.key, this.changingPassword = false});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  final _user = TextEditingController(text: kAppLockAutofillUsername);
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _currentFocus = FocusNode();
  final _pwFocus = FocusNode();
  final _pw2Focus = FocusNode();
  String? _error;
  bool _busy = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure0 = true;

  @override
  void dispose() {
    _user.dispose();
    _current.dispose();
    _pw.dispose();
    _pw2.dispose();
    _currentFocus.dispose();
    _pwFocus.dispose();
    _pw2Focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.changingPassword) {
      final old = _current.text;
      if (old.isEmpty) {
        setState(() => _error = 'Enter your current app password.');
        return;
      }
      final okOld = await AppLockService.instance.verifyPassword(old);
      if (!okOld) {
        setState(() => _error = 'Current password is incorrect.');
        return;
      }
    }

    final a = _pw.text;
    final b = _pw2.text;
    if (a.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (a != b) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.changingPassword) {
        await AppLockService.instance.updatePassword(a);
      } else {
        await AppLockService.instance.enableLock(a);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      TextInput.finishAutofillContext(shouldSave: true);
      AppLockService.instance.markUnlocked();
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(widget.changingPassword ? 'App password updated.' : 'App lock enabled.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.changingPassword ? 'Change app password' : 'Set app password'),
      ),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.changingPassword
                    ? 'Enter your current password, then a new one. Your password manager can save the new password.'
                    : 'Choose an app password separate from your wallet seed. Save it in your password manager when prompted.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.4),
              ),
              const SizedBox(height: 24),
              AppLockHiddenUsernameForAutofill(controller: _user),
              const SizedBox(height: 8),
              if (widget.changingPassword) ...[
                TextField(
                  controller: _current,
                  focusNode: _currentFocus,
                  obscureText: _obscure0,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  keyboardType: TextInputType.visiblePassword,
                  onSubmitted: (_) => _pwFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Current app password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure0 ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure0 = !_obscure0),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _pw,
                focusNode: _pwFocus,
                obscureText: _obscure1,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                textInputAction: TextInputAction.next,
                autofillHints: widget.changingPassword
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.newPassword, AutofillHints.password],
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => _pw2Focus.requestFocus(),
                decoration: InputDecoration(
                  labelText: widget.changingPassword ? 'New password' : 'App password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pw2,
                focusNode: _pw2Focus,
                obscureText: _obscure2,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: NeoTheme.green),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
