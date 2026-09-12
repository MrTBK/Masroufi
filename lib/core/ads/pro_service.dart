import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/brand.dart';

/// PRO remove-ads service (P3).
///
/// Two activation paths (Tunisia reality: Play Billing often unusable):
/// 1. Play Billing one-time purchase `masroufi_pro_2026`.
/// 2. Manual code, two shapes (verified offline, single-device):
///    `MASR-NNNNNN` (calculator: hex-sum × PIN + 2904 mod 10^6, seller
///    needs only a phone) or legacy `MASR-XXXX-XXXX` (HMAC-SHA256 of
///    install id with a release-time secret). You sell codes via D17 /
///    Ba9chich and the user pastes the code — no network needed.
///
/// The secret never ships in debug/test builds: manual codes verify only
/// against [manualSecret] provided via `--dart-define PRO_SECRET`.
/// Empty secret disables manual path (Play only).
abstract final class ProService {
  static const String manualSecret = String.fromEnvironment(
    'PRO_SECRET',
    defaultValue: '',
  );

  /// Numeric seller PIN for calculator-minted codes
  /// (`MASR-NNNNNN`). Release builds only, via `--dart-define PRO_PIN`.
  static const String proPin = String.fromEnvironment(
    'PRO_PIN',
    defaultValue: '',
  );

  /// Hex-digit sum of an 8-char install ref (A=10..F=15). -1 on bad input.
  static int hexSum(String ref8) {
    if (ref8.length != 8) return -1;
    var sum = 0;
    for (var i = 0; i < 8; i++) {
      final v = int.tryParse(ref8[i], radix: 16);
      if (v == null) return -1;
      sum += v;
    }
    return sum;
  }

  /// Calculator code for [deviceId]: (hexSum × PIN + 2904) mod 10^6,
  /// zero-padded to 6 digits. '' when PIN unset.
  static String pinCodeFor(String deviceId) {
    if (proPin.isEmpty) return '';
    final pin = int.tryParse(proPin);
    if (pin == null) return '';
    final ref8 = deviceId.replaceAll('-', '').toUpperCase();
    if (ref8.length < 8) return '';
    final sum = hexSum(ref8.substring(0, 8));
    if (sum < 0) return '';
    return ((sum * pin + 2904) % 1000000).toString().padLeft(6, '0');
  }

  /// Verify a manual code offline against this install's [deviceId].
  /// Two shapes: `MASR-NNNNNN` (calculator PIN path) and legacy
  /// `MASR-XXXXXXXX` (HMAC path). Empty device ids never verify,
  /// closing the old shared-code hole. Returns true on match.
  static bool verifyManualCode(String code, String deviceId) {
    if (deviceId.isEmpty) return false;
    final norm = code.trim().toUpperCase().replaceAll(' ', '').replaceAll(
      '-',
      '',
    );
    // Calculator path: MASR + 6 digits.
    if (RegExp(r'^MASR\d{6}$').hasMatch(norm)) {
      if (proPin.isEmpty) return false;
      return norm.substring(4) == pinCodeFor(deviceId);
    }
    if (manualSecret.isEmpty) return false;
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
