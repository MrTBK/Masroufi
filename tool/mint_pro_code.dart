import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Mint PRO manual codes for one install id.
///
/// Usage:
///   `PRO_PIN=<pin> dart run tool/mint_pro_code.dart <install-uuid>`
///   `PRO_SECRET=<secret> dart run tool/mint_pro_code.dart <install-uuid>`
///
/// Prints the calculator (`MASR-NNNNNN`) and/or HMAC (`MASR-XXXX-XXXX`)
/// code depending on which env is set. The buyer pastes it in
/// Settings → PRO → manual activation on the device showing that
/// install id. Codes verify nowhere else. Keep secrets out of git;
/// pass them only via env, and build releases with
/// `--dart-define PRO_SECRET=... --dart-define PRO_PIN=...`.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.isEmpty) {
    stderr.writeln(
      'usage: PRO_PIN=<pin> dart run tool/mint_pro_code.dart <install-uuid>',
    );
    exit(64);
  }
  final deviceId = args.first.trim();
  final pin = Platform.environment['PRO_PIN'] ?? '';
  final secret = Platform.environment['PRO_SECRET'] ?? '';
  if (pin.isEmpty && secret.isEmpty) {
    stderr.writeln('error: set PRO_PIN and/or PRO_SECRET env');
    exit(1);
  }
  if (pin.isNotEmpty) {
    final ref8 = deviceId.replaceAll('-', '').toUpperCase();
    if (ref8.length < 8) {
      stderr.writeln('error: install id too short');
      exit(1);
    }
    var sum = 0;
    for (var i = 0; i < 8; i++) {
      final v = int.tryParse(ref8[i], radix: 16);
      if (v == null) {
        stderr.writeln('error: install id not hex');
        exit(1);
      }
      sum += v;
    }
    final pinInt = int.tryParse(pin);
    if (pinInt == null) {
      stderr.writeln('error: PRO_PIN must be numeric');
      exit(1);
    }
    final code = ((sum * pinInt + 2904) % 1000000).toString().padLeft(6, '0');
    stdout.writeln('MASR-$code');
  }
  if (secret.isNotEmpty) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode('masroufi-pro:$deviceId'));
    final hex = digest.toString().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final suffix = hex.substring(0, 8);
    stdout.writeln('MASR-${suffix.substring(0, 4)}-${suffix.substring(4, 8)}');
  }
}
