import 'dart:convert';

import 'package:csv/csv.dart';

import '../../core/money/money.dart';

/// Pure backup codec (unit-testable, no I/O).
/// v2 adds: recurring_rules, category_budgets, savings_goals,
/// savings_contributions, debts, debt_payments (+ transactions gain
/// recurring_rule_id). v1 backups restore with new tables defaulting empty.
/// v3 adds: wallets gain isBalanceHidden, categories gain kind
/// (expense|income). v1/v2 backups restore with visible balances and
/// expense kinds.
/// v4 adds: categories gain priority (important|normal|fun). Older backups
/// restore with deterministic per-key defaults (customs → normal).
/// v5 adds: categories gain parentId (nullable parent ref). Older backups
/// restore with top-level parents (missing parentId → null, then backfilled).
/// v6 adds: wallets gain colorKey + design (card styling keys). Older
/// backups restore with teal/classic defaults.
/// v7 adds: txn_templates table (transaction templates). Older backups
/// restore with an empty template list.
/// Every row a JSON map with ISO dates.
abstract final class BackupCodec {
  static const int currentVersion = 7;
  static const int minSupportedVersion = 1;

  static const List<String> requiredKeysV1 = [
    'wallets',
    'categories',
    'transactions',
    'budgets',
    'settings',
  ];

  static const List<String> requiredKeysV2 = [
    'recurring_rules',
    'category_budgets',
    'savings_goals',
    'savings_contributions',
    'debts',
    'debt_payments',
  ];

  static const List<String> requiredKeysV3 = ['txn_templates'];

  static Map<String, dynamic> build(
    Map<String, List<Map<String, dynamic>>> tables,
  ) => {
    'version': currentVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    for (final k in [...requiredKeysV1, ...requiredKeysV2, ...requiredKeysV3])
      k: tables[k] ?? [],
  };

  static String encode(Map<String, dynamic> backup) => jsonEncode(backup);

  /// Returns null when valid, else an error code. v1-v6 accepted (upgraded).
  static String? validate(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return 'not-an-object';
    final v = decoded['version'];
    if (v != 1 &&
        v != 2 &&
        v != 3 &&
        v != 4 &&
        v != 5 &&
        v != 6 &&
        v != currentVersion) {
      return 'unsupported-version';
    }
    for (final k in requiredKeysV1) {
      if (decoded[k] is! List) return 'missing-$k';
    }
    if (v == currentVersion) {
      for (final k in [...requiredKeysV2, ...requiredKeysV3]) {
        if (decoded[k] is! List) return 'missing-$k';
      }
    }
    return null;
  }

  /// Decode + normalize: old backups gain empty newer tables; anything
  /// below v7 is stamped current (per-row new fields default on restore).
  static Map<String, dynamic>? tryDecode(String raw) {
    try {
      final d = jsonDecode(raw);
      if (validate(d) != null) return null;
      final m = d as Map<String, dynamic>;
      if ((m['version'] as num).toInt() < currentVersion) {
        return {
          ...m,
          'version': currentVersion,
          for (final k in [...requiredKeysV2, ...requiredKeysV3])
            if (m[k] == null) k: [],
        };
      }
      return m;
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

  /// CSV IMPORT pre-validation (pure, unit-testable). Parses [raw] CSV
  /// text into validated rows + per-row errors WITHOUT touching the DB.
  /// Nothing is committed here: the caller resolves wallet/category names
  /// against live repos and inserts only valid rows.
  ///
  /// Columns (case-insensitive, BOM-tolerant; unknown columns ignored):
  /// `date` (ISO `yyyy-MM-dd`, also `dd/MM/yyyy`), `type`
  /// (expense|income|transfer, default expense), `amount_millimes` (int)
  /// or `amount_tnd`/`amount` (parsed via `Money.parse`), `category`
  /// (name, optional), `wallet` (name), `to_wallet` (name, transfers),
  /// `note` (optional). Row numbers are 1-based file lines.
  static CsvImportPreview parseCsvImport(String raw) {
    final text = raw.replaceFirst(RegExp('^\uFEFF'), '');
    List<List<dynamic>> table;
    try {
      table = const CsvToListConverter().convert(text, eol: '\n');
    } catch (_) {
      try {
        table = const CsvToListConverter().convert(text);
      } catch (_) {
        return CsvImportPreview(
          rows: const [],
          errors: const [CsvImportError(row: 0, message: 'unparseable')],
        );
      }
    }
    // Drop fully-empty lines (trailing newline, blank rows).
    final lines = <List<dynamic>>[];
    for (final r in table) {
      if (r.any((c) => '$c'.trim().isNotEmpty)) lines.add(r);
    }
    if (lines.isEmpty) {
      return CsvImportPreview(
        rows: const [],
        errors: const [CsvImportError(row: 0, message: 'empty')],
      );
    }
    String norm(dynamic c) => '$c'.trim().toLowerCase();
    final header = [for (final c in lines.first) norm(c)];
    int col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final dateCol = col(['date', 'occurred_at', 'occurredat']);
    final typeCol = col(['type']);
    final millimesCol = col(['amount_millimes', 'amountmillimes']);
    final tndCol = col(['amount_tnd', 'amounttnd', 'amount']);
    final catCol = col(['category', 'categorie', 'تصنيف']);
    final walletCol = col(['wallet', 'portefeuille', 'محفظة']);
    final toWalletCol = col(['to_wallet', 'towallet']);
    final noteCol = col(['note']);
    if (dateCol < 0 || (millimesCol < 0 && tndCol < 0)) {
      return CsvImportPreview(
        rows: const [],
        errors: const [CsvImportError(row: 1, message: 'missing-columns')],
      );
    }
    String cell(List<dynamic> r, int c) =>
        (c < 0 || c >= r.length) ? '' : '${r[c]}'.trim();
    final rows = <CsvImportRow>[];
    final errors = <CsvImportError>[];
    for (var i = 1; i < lines.length; i++) {
      final r = lines[i];
      final lineno = i + 1;
      void bad(String m) => errors.add(CsvImportError(row: lineno, message: m));
      // Date.
      final dateRaw = cell(r, dateCol);
      final when = _parseImportDate(dateRaw);
      if (when == null) {
        bad('bad-date:$dateRaw');
        continue;
      }
      // Type.
      final typeRaw = cell(r, typeCol).toLowerCase();
      final type = typeRaw.isEmpty
          ? 'expense'
          : (typeRaw == 'expense' || typeRaw == 'income' || typeRaw == 'transfer'
                ? typeRaw
                : null);
      if (type == null) {
        bad('bad-type:$typeRaw');
        continue;
      }
      // Amount: millimes int wins; else Money.parse on the TND text.
      int? amount;
      final milRaw = cell(r, millimesCol);
      if (milRaw.isNotEmpty) {
        amount = int.tryParse(milRaw.replaceAll(RegExp(r'[\s,]'), ''));
      } else {
        final tndRaw = cell(r, tndCol);
        if (tndRaw.isNotEmpty) {
          try {
            amount = Money.parse(tndRaw).abs();
          } catch (_) {
            amount = null;
          }
        }
      }
      if (amount == null || amount <= 0) {
        bad('bad-amount:${milRaw.isNotEmpty ? milRaw : cell(r, tndCol)}');
        continue;
      }
      final wallet = cell(r, walletCol);
      if (wallet.isEmpty) {
        bad('missing-wallet');
        continue;
      }
      final toWallet = cell(r, toWalletCol);
      if (type == 'transfer' && toWallet.isEmpty) {
        bad('missing-to-wallet');
        continue;
      }
      rows.add(
        CsvImportRow(
          line: lineno,
          type: type,
          amountMillimes: amount,
          walletName: wallet,
          toWalletName: toWallet.isEmpty ? null : toWallet,
          categoryName: cell(r, catCol).isEmpty ? null : cell(r, catCol),
          occurredAt: when,
          note: cell(r, noteCol),
        ),
      );
    }
    return CsvImportPreview(rows: rows, errors: errors);
  }

  /// Accepts ISO `yyyy-MM-dd[THH:mm[:ss]]` and `dd/MM/yyyy`.
  static DateTime? _parseImportDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {}
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(s);
    if (m != null) {
      var year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      final month = int.parse(m.group(2)!);
      final day = int.parse(m.group(1)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }
    return null;
  }
}

/// One validated CSV row, ready for name resolution + insert.
/// Wallet/category travel as NAMES; the caller maps them to ids.
class CsvImportRow {
  final int line;
  final String type;
  final int amountMillimes;
  final String walletName;
  final String? toWalletName;
  final String? categoryName;
  final DateTime occurredAt;
  final String note;
  const CsvImportRow({
    required this.line,
    required this.type,
    required this.amountMillimes,
    required this.walletName,
    this.toWalletName,
    this.categoryName,
    required this.occurredAt,
    this.note = '',
  });
}

/// One rejected CSV row: 1-based file line + machine-readable reason
/// (`bad-date:<v>`, `bad-type:<v>`, `bad-amount:<v>`, `missing-wallet`,
/// `missing-to-wallet`, `unknown-wallet:<v>`, `unknown-to-wallet:<v>`,
/// `missing-columns`, `empty`, `unparseable`).
class CsvImportError {
  final int row;
  final String message;
  const CsvImportError({required this.row, required this.message});
}

/// Result of [BackupCodec.parseCsvImport]: valid rows + error report.
class CsvImportPreview {
  final List<CsvImportRow> rows;
  final List<CsvImportError> errors;
  const CsvImportPreview({required this.rows, required this.errors});
}
