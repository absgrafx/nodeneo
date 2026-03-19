import 'package:flutter/material.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'theme.dart';

class RedPillApp extends StatefulWidget {
  const RedPillApp({super.key});

  @override
  State<RedPillApp> createState() => _RedPillAppState();
}

class _RedPillAppState extends State<RedPillApp> {
  bool _hasWallet = false;

  void _onWalletCreated() {
    setState(() => _hasWallet = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedPill',
      debugShowCheckedModeBanner: false,
      theme: RedPillTheme.dark,
      home: _hasWallet
          ? const HomeScreen()
          : OnboardingScreen(onComplete: _onWalletCreated),
    );
  }
}
