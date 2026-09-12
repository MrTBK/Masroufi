import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/brand.dart';

/// PRO remove-ads service (P3).
///
/// Two activation paths (Tunisia reality: Play Billing often unusable):
/// 1. Play Billing one-time purchase `masroufi_pro_2026`.
/// 2. Manual code `MASR-XXXX-XXXX` (HMAC-SHA256 of the install id with a
///    release-time secret, verified offline). Single-device: a code
///    minted for one install verifies nowhere else, so codes cannot be
///    shared. Legacy empty-id codes are rejected.
///
/// The secret never ships in debug/test builds: manual codes verify only
/// against [manualSecret] provided via `--dart-define PRO_SECRET`.
/// Empty secret disables manual path (Play only).
abstract final class ProService {
  static const String manualSecret = String.fromEnvironment(
    'PRO_SECRET',
    defaultValue: '',
  );

  /// Verify a manual code offline against this install's [deviceId].
  /// Format `MASR-XXXX-XXXX` (uppercase alnum). Empty device ids never
  /// verify, closing the old shared-code hole. Returns true on match.
  static bool verifyManualCode(String code, String deviceId) {
    if (manualSecret.isEmpty) return false;
    if (deviceId.isEmpty) return false;
    final norm = code
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    if (!RegExp(r'^MASR[A-Z0-9]{8}$').hasMatch(norm)) return false;
    final suffix = norm.substring(4); // 8 chars
    final hmac = Hmac(sha256, utf8.encode(manualSecret));
    final digest = hmac.convert(utf8.encode('masroufi-pro:$deviceId'));
    final hex = digest.toString().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return hex.startsWith(suffix);
  }

  /// Generate a code for a device (run by you offline, e.g. `dart run`).
  static String mintManualCode(String deviceId) {
    final hmac = Hmac(sha256, utf8.encode(manualSecret));
    final digest = hmac.convert(utf8.encode('masroufi-pro:$deviceId'));
    final hex = digest.toString().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final suffix = hex.substring(0, 8);
    return 'MASR-${suffix.substring(0, 4)}-${suffix.substring(4, 8)}';
  }

  /// Query Play product details for the PRO SKU. Null on store
  /// unavailable (offline, desktop, tests) — caller shows manual path.
  static Future<ProductDetails?> queryProProduct() async {
    try {
      final iap = InAppPurchase.instance;
      final available = await iap.isAvailable();
      if (!available) return null;
      final resp = await iap.queryProductDetails({Brand.proRemoveAdsSku});
      if (resp.productDetails.isEmpty) return null;
      return resp.productDetails.first;
    } catch (_) {
      return null;
    }
  }

  /// Start purchase flow. Returns the purchase stream for the UI to
  /// listen to; completion is delivered via
  /// `InAppPurchase.instance.purchaseStream`.
  static Future<bool> buyPro(ProductDetails product) async {
    try {
      return await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      return false;
    }
  }
}
