import 'dart:async';
import 'dart:io';

/// Single cheap online probe. DNS lookup only, never fetches content.
///
/// No new dependency, no new permission: INTERNET already merges in via
/// google_mobile_ads. [lookup] and [timeout] are injectable so unit tests
/// stay deterministic and offline-safe.
Future<bool> isOnline({
  Future<List<InternetAddress>> Function(String host)? lookup,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final resolve = lookup ?? InternetAddress.lookup;
    final addrs = await resolve('google.com').timeout(timeout);
    return addrs.isNotEmpty;
  } catch (_) {
    return false;
  }
}
