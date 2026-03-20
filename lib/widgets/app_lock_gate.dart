import 'package:flutter/material.dart';

import '../screens/security/app_lock_screen.dart';
import '../services/app_lock_service.dart';

/// When app lock is enabled, shows [AppLockScreen] until unlocked.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    AppLockService.instance.unlocked.addListener(_onUnlocked);
  }

  void _onUnlocked() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await AppLockService.instance.applyColdStartPolicy();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    AppLockService.instance.unlocked.removeListener(_onUnlocked);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF22C55E))),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockService.instance.unlocked,
      builder: (context, open, _) {
        if (!open) return const AppLockScreen();
        return widget.child;
      },
    );
  }
}
