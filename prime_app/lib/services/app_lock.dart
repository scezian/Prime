import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// App-level lock: gates the whole app behind a PIN, with optional
/// fingerprint/face unlock as a faster path when the device supports it.
///
/// Storage: PIN lives in the same Keystore-backed secure storage as the
/// laptop unlock password (see SecureCredentials) — encrypted at rest,
/// never leaves the device. This is a local access gate, not a network
/// credential, so it doesn't need a network-safe hash; storing it directly
/// alongside the existing unlock-password pattern keeps things consistent.
class AppLock {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _enabledKey = 'prime_applock_enabled';
  static const _pinKey = 'prime_applock_pin';
  static const _biometricKey = 'prime_applock_biometric';

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isEnabled() async {
    final v = await _storage.read(key: _enabledKey);
    return v == 'true';
  }

  static Future<bool> biometricPreferred() async {
    final v = await _storage.read(key: _biometricKey);
    return v == 'true';
  }

  static Future<void> setBiometricPreferred(bool value) =>
      _storage.write(key: _biometricKey, value: value.toString());

  /// Enables the lock with the given PIN (4-8 digits recommended, not enforced here).
  static Future<void> enable(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  /// Disables the lock and forgets the stored PIN.
  static Future<void> disable() async {
    await _storage.write(key: _enabledKey, value: 'false');
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _biometricKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored != null && stored == pin;
  }

  static Future<void> changePin(String newPin) => _storage.write(key: _pinKey, value: newPin);

  /// Whether this device even has fingerprint/face hardware enrolled —
  /// used to decide whether to show the biometric option in Settings and
  /// the fingerprint button on the lock screen at all.
  static Future<bool> deviceHasBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts biometric unlock. Returns true only on an explicit successful
  /// authentication — unlike BiometricAuth.confirm (used for in-app action
  /// confirmations), this fails CLOSED, since this is the primary gate,
  /// not a secondary check with a PIN fallback already satisfied.
  static Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Prime',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
