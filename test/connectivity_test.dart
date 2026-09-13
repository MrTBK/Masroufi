import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/net/connectivity.dart';

void main() {
  group('isOnline', () {
    test('true when DNS resolves', () async {
      Future<List<InternetAddress>> ok(String _) async => [
        InternetAddress('142.250.0.1'),
      ];
      expect(await isOnline(lookup: ok), isTrue);
    });

    test('false when DNS returns empty', () async {
      Future<List<InternetAddress>> empty(String _) async => [];
      expect(await isOnline(lookup: empty), isFalse);
    });

    test('false when lookup throws (offline)', () async {
      Future<List<InternetAddress>> boom(String _) async =>
          throw const SocketException('no route');
      expect(await isOnline(lookup: boom), isFalse);
    });

    test('false on timeout instead of hanging', () async {
      Future<List<InternetAddress>> slow(String _) =>
          Completer<List<InternetAddress>>().future;
      final sw = Stopwatch()..start();
      expect(
        await isOnline(lookup: slow, timeout: const Duration(milliseconds: 50)),
        isFalse,
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
