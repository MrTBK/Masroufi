import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Mint a single-device PRO manual code for one install id.
///
/// Usage:
///   `PRO_SECRET=<release-secret> dart run tool/mint_pro_code.dart <install-uuid>`
///
/// Prints `MASR-XXXX-XXXX`. The buyer pastes it in Settings → PRO →
/// manual activation on the device showing that install id. The code
/// verifies nowhere else. Keep PRO_SECRET out of git; pass it only via
/// env, and build releases with `--dart-define PRO_SECRET=$PRO_SECRET`.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.isEmpty) {
    stderr.writeln('usage: PRO_SECRET=<secret> dart run tool/mint_pro_code.dart <install-uuid>');
    exit(64);
  }
  final secret = Platform.environment['PRO_SECRET'] ?? '';
  if (secret.isEmpty) {
    stderr.writeln('error: PRO_SECRET env is empty');
    exit(1);
  }
  final deviceId = args.first.trim();
  final hmac = Hmac(sha256, utf8.encode(secret));
  final digest = hmac.convert(utf8.encode('masroufi-pro:$deviceId'));
  final hex = digest.toString().toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]'),
    '',
  );
  final suffix = hex.substring(0, 8);
  stdout.writeln('MASR-${suffix.substring(0, 4)}-${suffix.substring(4, 8)}');
}
