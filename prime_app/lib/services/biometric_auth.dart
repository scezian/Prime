import 'package:local_auth/local_auth.dart';

/// Gates sensitive/destructive actions behind the device's fingerprint,
/// face unlock, or PIN/pattern (whichever the device has set up).
///
/// Design choice: if the device has no authentication method configured at
/// all (isDeviceSupported() == false), or if the plugin itself throws an
/// unexpected platform error, this fails OPEN — the action proceeds rather
/// than being permanently blocked. The gate only adds a layer on top of the
/// existing tap-to-confirm flow; a broken/unavailable auth plugin shouldn't
/// brick core app functionality. If the user is actually prompted and
/// cancels or fails, that correctly fails CLOSED (action does not proceed).
class BiometricAuth {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the action should proceed.
  static Future<bool> confirm(String reason) async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return true;

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // allow PIN/pattern fallback, not fingerprint-only
        persistAcrossBackgrounding: true, // survives the app briefly backgrounding mid-prompt
      );
    } catch (_) {
      return true;
    }
  }
}
