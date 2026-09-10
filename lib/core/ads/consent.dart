import 'package:user_messaging_platform/user_messaging_platform.dart';

/// UMP consent helper (P2). Best-effort: any failure means "no consent"
/// and ads stay off. Never blocks startup or finance flows.
abstract final class AdsConsent {
  static bool _requested = false;

  /// Request consent info + show form when required (EU/TN). Returns
  /// true when personalized ads may load. Safe to call repeatedly;
  /// the form shows at most once per launch.
  static Future<bool> requestIfRequired() async {
    if (_requested) return false;
    _requested = true;
    try {
      final info = await UserMessagingPlatform.instance
          .requestConsentInfoUpdate();
      if (info.consentStatus == ConsentStatus.required) {
        await UserMessagingPlatform.instance.showConsentForm();
      }
      final after = await UserMessagingPlatform.instance.getConsentInfo();
      return after.consentStatus != ConsentStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Reset for tests / settings "reset consent".
  static void resetForTest() => _requested = false;
}
