import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cloud-AI gateway (P4, opt-in only).
///
/// - Called ONLY when `ai_cloud_enabled` is true and the user taps
///   "Explain". Never auto-sends, never sends notes unless
///   `ai_include_notes` is true (currently notes are never in the
///   payload — see [AiSummaryBuilder]).
/// - The LLM API key lives on YOUR proxy, never in the APK. Endpoint
///   via `--dart-define AI_PROXY_URL=https://.../explain`.
/// - Offline / PRO-quota / failure → caller falls back to on-device
///   template insights. All failures are silent-safe (return null).
class AiGateway {
  static const String proxyUrl = String.fromEnvironment(
    'AI_PROXY_URL',
    defaultValue: '',
  );

  final http.Client _client;
  AiGateway({http.Client? client}) : _client = client ?? http.Client();

  /// Explain a compact summary JSON. Returns localized explanation text
  /// or null when unavailable (offline, no proxy, quota, error).
  Future<String?> explain({
    required String summaryJson,
    required String lang,
    required bool isPro,
  }) async {
    if (proxyUrl.isEmpty) return null;
    try {
      final resp = await _client
          .post(
            Uri.parse(proxyUrl),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'lang': lang,
              'pro': isPro,
              'summary': jsonDecode(summaryJson),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is Map && data['text'] is String) {
        final text = (data['text'] as String).trim();
        return text.isEmpty ? null : text;
      }
      return null;
    } catch (_) {
      debugPrint('AiGateway: offline or proxy unavailable');
      return null;
    }
  }
}
