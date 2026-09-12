import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/ads/pro_service.dart';

/// Single-device manual codes. Run with test secrets:
/// flutter test test/pro_code_test.dart --dart-define PRO_SECRET=t --dart-define TEST_PRO_SECRET=t --dart-define PRO_PIN=123456 --dart-define TEST_PRO_PIN=123456
const _testSecret = String.fromEnvironment('TEST_PRO_SECRET', defaultValue: '');
const _testPin = String.fromEnvironment('TEST_PRO_PIN', defaultValue: '');

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

    test('pin math: hex sum example 25371DD0 -> 44', () {
      expect(ProService.hexSum('25371DD0'), 44);
      expect(ProService.hexSum('tooshort'), -1);
      expect(ProService.hexSum('ZZZZZZZZ'), -1);
    });

    test('pin code round-trip is per-device', () {
      if (_testPin.isEmpty || ProService.proPin.isEmpty) return;
      const uuid = '25371dd0-aaaa-bbbb-cccc-dddddddddddd';
      final code = ProService.pinCodeFor(uuid);
      expect(code, hasLength(6));
      expect(ProService.verifyManualCode('MASR-$code', uuid), isTrue);
      expect(
        ProService.verifyManualCode(
          'MASR-$code',
          'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        ),
        isFalse,
      );
      expect(ProService.verifyManualCode('MASR-000000', uuid), isFalse);
    });
  });
}
