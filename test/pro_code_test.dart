import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/ads/pro_service.dart';

/// Single-device manual codes. Run with a test secret:
/// flutter test test/pro_code_test.dart --dart-define PRO_SECRET=t --dart-define TEST_PRO_SECRET=t
const _testSecret = String.fromEnvironment('TEST_PRO_SECRET', defaultValue: '');

String _mint(String deviceId) {
  final hmac = Hmac(sha256, utf8.encode(_testSecret));
  final digest = hmac.convert(utf8.encode('masroufi-pro:$deviceId'));
  final hex = digest.toString().toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]'),
    '',
  );
  final s = hex.substring(0, 8);
  return 'MASR-${s.substring(0, 4)}-${s.substring(4, 8)}';
}

void main() {
  test('legacy empty-id codes never verify', () {
    expect(ProService.verifyManualCode('MASR-AB12-CD34', ''), isFalse);
  });

  test('bad format never verifies', () {
    expect(ProService.verifyManualCode('hello', 'device-1'), isFalse);
    expect(ProService.verifyManualCode('MASR-!!!-???', 'device-1'), isFalse);
  });

  group('with test secret', () {
    test('round-trip verifies on same device only', () {
      if (_testSecret.isEmpty || ProService.manualSecret.isEmpty) return;
      final code = _mint('device-1');
      expect(ProService.verifyManualCode(code, 'device-1'), isTrue);
      expect(ProService.verifyManualCode(code, 'device-2'), isFalse);
    });
  });
}
