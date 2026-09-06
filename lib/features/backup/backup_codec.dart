import 'dart:convert';

import 'package:csv/csv.dart';

/// Pure backup codec (unit-testable, no I/O).
/// Backup format v1: {version:1, exportedAt, wallets, categories,
/// transactions, budgets, settings} — every row a JSON map with ISO dates.
abstract final class BackupCodec {
  static const int currentVersion = 1;

  static const List<String> requiredKeys = [
    'wallets',
    'categories',
    'transactions',
    'budgets',
    'settings',
  ];

  static Map<String, dynamic> build(
    Map<String, List<Map<String, dynamic>>> tables,
  ) => {
    'version': currentVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    for (final k in requiredKeys) k: tables[k] ?? [],
  };

  static String encode(Map<String, dynamic> backup) => jsonEncode(backup);

  /// Returns null when valid, else an error code.
  static String? validate(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return 'not-an-object';
    if (decoded['version'] != currentVersion) return 'unsupported-version';
    for (final k in requiredKeys) {
      if (decoded[k] is! List) return 'missing-$k';
    }
    return null;
  }

  static Map<String, dynamic>? tryDecode(String raw) {
    try {
      final d = jsonDecode(raw);
      if (validate(d) != null) return null;
      return d as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// CSV export rows (UTF-8; caller prepends BOM for Excel).
  static String buildCsv(List<Map<String, dynamic>> rows) {
    const header = [
      'date',
      'type',
      'amount_millimes',
      'amount_tnd',
      'category',
      'wallet',
      'to_wallet',
      'note',
    ];
    return const ListToCsvConverter().convert([
      header,
      for (final r in rows) [for (final h in header) r[h] ?? ''],
    ]);
  }
}
