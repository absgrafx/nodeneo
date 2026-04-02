import 'package:flutter/material.dart';
import 'app.dart';
import 'macos_splash_removal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NodeNeoApp());
  scheduleMacOsNativeSplashRemoval();
}
