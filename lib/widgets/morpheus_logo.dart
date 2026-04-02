import 'package:flutter/material.dart';

/// Node Neo glasses mark — used on home screen, lock screen, onboarding.
class NeoLogo extends StatelessWidget {
  const NeoLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/splash_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
