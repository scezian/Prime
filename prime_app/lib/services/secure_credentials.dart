import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the laptop unlock password on-device only, encrypted via the
/// Android Keystore. Never written to the daemon's disk — sent fresh with
/// each unlock request and used immediately there, not persisted.
class SecureCredentials {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _unlockPasswordKey = 'prime_unlock_password';

  static Future<String?> getUnlockPassword() => _storage.read(key: _unlockPasswordKey);

  static Future<void> setUnlockPassword(String password) =>
      _storage.write(key: _unlockPasswordKey, value: password);

  static Future<void> clearUnlockPassword() => _storage.delete(key: _unlockPasswordKey);
}
