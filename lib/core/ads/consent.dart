import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// UMP consent helper (P2) via google_mobile_ads' bundled UMP.
/// Best-effort: any failure means "no consent" and ads stay off.
/// Never blocks startup or finance flows.
abstract final class AdsConsent {
  static bool _requested = false;

  /// Request consent info + show form when required (EU/TN). Returns
  /// true when personalized ads may load. Safe to call repeatedly;
  /// the form shows at most once per launch.
  static Future<bool> requestIfRequired() async {
    if (_requested) return false;
    _requested = true;
    try {
      final done = Completer<bool>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            final available = await ConsentInformation.instance
                .isConsentFormAvailable();
            if (available) {
              final dismissed = Completer<void>();
              ConsentForm.loadConsentForm(
                (form) => form.show((_) {
                  if (!dismissed.isCompleted) dismissed.complete();
                }),
                (_) {
                  if (!dismissed.isCompleted) dismissed.complete();
                },
              );
              await dismissed.future.timeout(const Duration(seconds: 30));
            }
            final status = await ConsentInformation.instance
                .getConsentStatus();
            if (!done.isCompleted) {
              done.complete(status != ConsentStatus.required);
            }
          } catch (_) {
            if (!done.isCompleted) done.complete(false);
          }
        },
        (_) {
          if (!done.isCompleted) done.complete(false);
        },
      );
      return await done.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Reset for tests / settings "reset consent".
  static Future<void> resetForTest() async {
    _requested = false;
    try {
      await ConsentInformation.instance.reset();
    } catch (_) {}
  }
}
