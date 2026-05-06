import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

/// User-facing nouns/verbs for biometric authentication, adapted to the
/// platform AND to what the device actually has enrolled.
///
/// "Face ID" and "Touch ID" are Apple trademarks and only appear on Apple
/// platforms. On Android we follow Google's Material guidance and use
/// "Fingerprint" / "Face Unlock" when we can identify a single modality, or
/// the umbrella term **"biometrics"** when multiple/iris/strong/weak modalities
/// are reported. On Windows we say "Windows Hello". Linux and unknown
/// platforms get the safe generic noun.
///
/// All screens that talk about the biometric unlock path should use these
/// labels instead of hard-coding "Face ID" so the same UI reads naturally on
/// every form factor.
class BiometricLabels {
  /// Display-name proper noun. Examples: "Face ID", "Touch ID",
  /// "Face ID & Touch ID", "Fingerprint", "Face Unlock", "biometrics",
  /// "Windows Hello".
  final String name;

  /// Short label for the primary unlock CTA. Always starts with "Use ".
  final String unlockCta;

  /// Title for setup choice card / unlock-method picker.
  /// Examples: "Lock with Face ID", "Lock with Fingerprint",
  /// "Lock with biometrics".
  final String setupTitle;

  /// Reason string handed to the system biometric prompt's
  /// `localizedReason`. Composed with the app name at call site.
  final String confirmReasonVerb;

  /// True iff the device supports any form of biometric unlock.
  final bool available;

  const BiometricLabels._({
    required this.name,
    required this.unlockCta,
    required this.setupTitle,
    required this.confirmReasonVerb,
    required this.available,
  });

  /// Best guess synchronously from platform alone — cheap default while an
  /// async [probe] is in flight. iPhones since X have Face ID, but the small
  /// number of older devices (iPhone 8 / SE) have Touch ID; this default
  /// favours Face ID and the async probe corrects it.
  static BiometricLabels get platformGuess => _platformGuess;

  static const _faceId = BiometricLabels._(
    name: 'Face ID',
    unlockCta: 'Use Face ID',
    setupTitle: 'Lock with Face ID',
    confirmReasonVerb: 'Confirm Face ID for',
    available: true,
  );
  static const _touchId = BiometricLabels._(
    name: 'Touch ID',
    unlockCta: 'Use Touch ID',
    setupTitle: 'Lock with Touch ID',
    confirmReasonVerb: 'Confirm Touch ID for',
    available: true,
  );
  static const _faceAndTouchId = BiometricLabels._(
    name: 'Face ID / Touch ID',
    unlockCta: 'Use Face ID / Touch ID',
    setupTitle: 'Lock with Face ID / Touch ID',
    confirmReasonVerb: 'Confirm biometrics for',
    available: true,
  );
  static const _androidFingerprint = BiometricLabels._(
    name: 'Fingerprint',
    unlockCta: 'Use Fingerprint',
    setupTitle: 'Lock with Fingerprint',
    confirmReasonVerb: 'Confirm fingerprint for',
    available: true,
  );
  static const _androidFace = BiometricLabels._(
    name: 'Face Unlock',
    unlockCta: 'Use Face Unlock',
    setupTitle: 'Lock with Face Unlock',
    confirmReasonVerb: 'Confirm face for',
    available: true,
  );
  static const _androidBiometric = BiometricLabels._(
    name: 'biometrics',
    unlockCta: 'Use biometrics',
    setupTitle: 'Lock with biometrics',
    confirmReasonVerb: 'Confirm biometrics for',
    available: true,
  );
  static const _windowsHello = BiometricLabels._(
    name: 'Windows Hello',
    unlockCta: 'Use Windows Hello',
    setupTitle: 'Lock with Windows Hello',
    confirmReasonVerb: 'Confirm Windows Hello for',
    available: true,
  );
  static const _genericAvailable = BiometricLabels._(
    name: 'biometrics',
    unlockCta: 'Use biometrics',
    setupTitle: 'Lock with biometrics',
    confirmReasonVerb: 'Confirm biometrics for',
    available: true,
  );
  static const _unavailable = BiometricLabels._(
    name: 'biometrics',
    unlockCta: 'Use biometrics',
    setupTitle: 'Lock with biometrics',
    confirmReasonVerb: 'Confirm biometrics for',
    available: false,
  );

  static BiometricLabels get _platformGuess {
    if (Platform.isIOS) return _faceId;
    if (Platform.isMacOS) return _touchId;
    if (Platform.isAndroid) return _androidBiometric;
    if (Platform.isWindows) return _windowsHello;
    return _genericAvailable;
  }

  /// Probe the platform via [LocalAuthentication] and return the most precise
  /// label set we can derive. Returns the [_unavailable] sentinel when the
  /// device has no biometric capability or the user has none enrolled.
  static Future<BiometricLabels> probe([LocalAuthentication? auth]) async {
    final a = auth ?? LocalAuthentication();
    try {
      final supported = await a.isDeviceSupported();
      if (!supported) return _unavailable;
      final canCheck = await a.canCheckBiometrics;
      if (!canCheck) return _unavailable;
      final types = await a.getAvailableBiometrics();
      if (types.isEmpty) {
        // Capability present but nothing enrolled — still return platform
        // guess so copy doesn't silently regress to "biometrics".
        return platformGuess;
      }
      return _resolveFromTypes(types);
    } catch (_) {
      return _unavailable;
    }
  }

  static BiometricLabels _resolveFromTypes(List<BiometricType> types) {
    final hasFace = types.contains(BiometricType.face);
    final hasFingerprint = types.contains(BiometricType.fingerprint);

    if (Platform.isIOS) {
      if (hasFace && hasFingerprint) return _faceAndTouchId;
      if (hasFace) return _faceId;
      if (hasFingerprint) return _touchId;
    }
    if (Platform.isMacOS) {
      // Macs only ship Touch ID today; treat any reported biometric as Touch ID.
      return _touchId;
    }
    if (Platform.isAndroid) {
      if (hasFace && hasFingerprint) return _androidBiometric;
      if (hasFace) return _androidFace;
      if (hasFingerprint) return _androidFingerprint;
      return _androidBiometric;
    }
    if (Platform.isWindows) return _windowsHello;
    return _genericAvailable;
  }
}
