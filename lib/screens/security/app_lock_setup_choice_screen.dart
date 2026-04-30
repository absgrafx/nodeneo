import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../constants/app_brand.dart';
import '../../services/app_lock_service.dart';
import '../../services/form_factor.dart';
import '../../theme.dart';
import 'app_lock_setup_screen.dart';

/// Landing page for "Turn on app lock". Lets the user pick **Face ID / Touch
/// ID** as the primary path (no password required) or fall back to the
/// classic password flow. We always present the biometric option first when
/// the device supports it — biometrics-first is the iOS-native pattern users
/// expect from Apple Wallet, 1Password, banking apps, etc.
class AppLockSetupChoiceScreen extends StatefulWidget {
  const AppLockSetupChoiceScreen({super.key});

  @override
  State<AppLockSetupChoiceScreen> createState() =>
      _AppLockSetupChoiceScreenState();
}

class _AppLockSetupChoiceScreenState extends State<AppLockSetupChoiceScreen> {
  final _auth = LocalAuthentication();
  bool _bioAvailable = false;
  bool _checking = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _probeBiometrics();
  }

  Future<void> _probeBiometrics() async {
    bool can = false;
    try {
      final supported = await _auth.isDeviceSupported();
      can = supported && await _auth.canCheckBiometrics;
    } catch (_) {
      can = false;
    }
    if (!mounted) return;
    setState(() {
      _bioAvailable = can;
      _checking = false;
    });
  }

  Future<void> _enableBiometricOnly() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Verify the user can actually pass a biometric prompt before flipping
      // the storage flag. Otherwise a misconfigured device (no enrolled face,
      // passcode missing) would lock the user out on next cold start.
      final ok = await _auth.authenticate(
        localizedReason: 'Confirm Face ID for ${AppBrand.displayName} app lock',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!ok) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await AppLockService.instance.enableBiometricLockOnly();
      AppLockService.instance.markUnlocked();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        const SnackBar(content: Text('App lock enabled with Face ID.')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Biometric authentication failed.'),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enablePassword() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AppLockSetupScreen(changingPassword: false),
      ),
    );
    if (!mounted) return;
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Turn on app lock')),
      body: SafeArea(
        child: MaxContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Choose how you want to unlock ${AppBrand.displayName}. '
                'You can change this later in Preferences.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _LockChoiceCard(
                icon: Icons.face_outlined,
                title: 'Lock with Face ID / Touch ID',
                subtitle: _bioAvailable
                    ? 'Recommended. Unlocks instantly on this device. '
                        'You can add a backup password later.'
                    : 'Not available on this device. Set up Face ID or '
                        'Touch ID in Settings to use this option.',
                primary: _bioAvailable,
                enabled: _bioAvailable && !_busy && !_checking,
                cta: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Use Face ID'),
                onTap: _enableBiometricOnly,
              ),
              const SizedBox(height: 12),
              _LockChoiceCard(
                icon: Icons.password_outlined,
                title: 'Lock with a password',
                subtitle: 'A separate app password (not your wallet seed). '
                    'Useful if biometrics are unavailable or you want a '
                    'shared device password.',
                primary: !_bioAvailable,
                enabled: !_busy,
                cta: const Text('Set a password'),
                onTap: _enablePassword,
              ),
              const SizedBox(height: 16),
              Text(
                'Either option, your wallet seed phrase / private key always '
                'works as a recovery path if you get locked out.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final bool enabled;
  final Widget cta;
  final VoidCallback onTap;

  const _LockChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.enabled,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: NeoTheme.mainPanelFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primary
              ? NeoTheme.green.withValues(alpha: 0.6)
              : NeoTheme.mainPanelOutline(0.4),
          width: primary ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: primary ? NeoTheme.green : null),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (primary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NeoTheme.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Recommended',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: NeoTheme.green,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: primary
                ? FilledButton(
                    onPressed: enabled ? onTap : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: NeoTheme.green,
                    ),
                    child: cta,
                  )
                : OutlinedButton(
                    onPressed: enabled ? onTap : null,
                    child: cta,
                  ),
          ),
        ],
      ),
    );
  }
}
