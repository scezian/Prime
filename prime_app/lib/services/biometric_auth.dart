import 'package:local_auth/local_auth.dart';

/// Gates sensitive/destructive actions behind the device's fingerprint,
/// face unlock, or PIN/pattern (whichever the device has set up).
///
/// Fails CLOSED: if the device has no authentication method configured
/// (isDeviceSupported() == false), or if the plugin throws an unexpected
/// platform error, the action is blocked rather than allowed through.
/// A broken/unavailable auth plugin should not silently let destructive
/// actions bypass confirmation. If the user is prompted and cancels or
/// fails, that also correctly fails CLOSED (action does not proceed).
class BiometricAuth {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true only if the user actually authenticated successfully.
  static Future<bool> confirm(String reason) async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // allow PIN/pattern fallback, not fingerprint-only
        persistAcrossBackgrounding: true, // survives the app briefly backgrounding mid-prompt
      );
    } catch (_) {
      return false;
    }
  }
}
