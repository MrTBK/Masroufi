import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../money/money.dart';

/// One top-category line in the statement. All int millimes.
typedef StatementCategory = ({String name, int total});

/// Pure monthly-statement data (unit-testable, no I/O, no widgets).
///
/// Built from existing [AnalyticsRepo] outputs: month income/expense,
/// per-category totals, budget vs actual, txn count. Money stays int
/// millimes; formatting via [Money.format] only at render time.
class MonthlyStatementData {
  final int year;
  final int month;
  final int incomeMillimes;
  final int expenseMillimes;
  final int txnCount;
  final List<StatementCategory> topCategories;
  final int? budgetMillimes;
  final int? budgetSpentMillimes;

  const MonthlyStatementData({
    required this.year,
    required this.month,
    required this.incomeMillimes,
    required this.expenseMillimes,
    required this.txnCount,
    this.topCategories = const [],
    this.budgetMillimes,
    this.budgetSpentMillimes,
  });

  int get netMillimes => incomeMillimes - expenseMillimes;

  /// Budget remaining (positive) or over-spend (negative), null when no budget.
  int? get budgetRemaining =>
      budgetMillimes == null || budgetSpentMillimes == null
      ? null
      : budgetMillimes! - budgetSpentMillimes!;
}

abstract final class MonthlyStatementBuilder {
  /// Pure data assembly from repo outputs. Sorts top categories desc,
  /// caps at 5, drops zero/negative. No I/O.
  static MonthlyStatementData build({
    required int year,
    required int month,
    required int incomeMillimes,
    required int expenseMillimes,
    required int txnCount,
    Map<String?, int> byCategory = const {},
    Map<String, String> categoryNames = const {},
    int? budgetMillimes,
    int? budgetSpentMillimes,
  }) {
    final entries = byCategory.entries
        .where((e) => e.value > 0)
        .map(
          (e) => (
            name: e.key == null
                ? '—'
                : (categoryNames[e.key] ?? e.key!),
            total: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return MonthlyStatementData(
      year: year,
      month: month,
      incomeMillimes: incomeMillimes,
      expenseMillimes: expenseMillimes,
      txnCount: txnCount,
      topCategories: entries.take(5).toList(),
      budgetMillimes: budgetMillimes,
      budgetSpentMillimes: budgetSpentMillimes,
    );
  }

  /// Localized month label: "September 2026" / "septembre 2026" /
  /// Arabic month name + year. Pure map, no intl (offline-safe).
  static String monthLabel(int year, int month, String lang) {
    const en = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const fr = [
      '',
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    const ar = [
      '',
      'جانفي',
      'فيفري',
      'مارس',
      'أفريل',
      'ماي',
      'جوان',
      'جويلية',
      'أوت',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final name = switch (lang) {
      'fr' => fr[month],
      'ar' => ar[month],
      _ => en[month],
    };
    return '$name $year';
  }

  /// Render PDF bytes. [arabicFont] is the Amiri TTF bytes bundled under
  /// assets/fonts (SIL OFL); when null, falls back to Helvetica (Latin
  /// only — Arabic shaping then degrades, but numbers still render).
  /// Attaches minus signs to amounts (never detached) by formatting via
  /// [Money.format] into a single run.
  static Future<Uint8List> buildPdf({
    required MonthlyStatementData data,
    required String lang,
    ByteData? arabicFont,
  }) async {
    final base = arabicFont == null
        ? pw.Font.helvetica()
        : pw.Font.ttf(arabicFont);
    final doc = pw.Document();
    final label = monthLabel(data.year, data.month, lang);
    String fmt(int v) => Money.format(v, lang: lang);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Masroufi — مصروفي',
              style: pw.TextStyle(font: base, fontSize: 20),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              label,
              style: pw.TextStyle(font: base, fontSize: 14),
            ),
            pw.Divider(),
            pw.Text(
              '${fmt(data.incomeMillimes)} / ${fmt(data.expenseMillimes)}',
              style: pw.TextStyle(font: base, fontSize: 12),
            ),
            pw.Text(
              fmt(data.netMillimes),
              style: pw.TextStyle(font: base, fontSize: 12),
            ),
            pw.Text(
              'txn: ${data.txnCount}',
              style: pw.TextStyle(font: base, fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Top', style: pw.TextStyle(font: base, fontSize: 12)),
            for (final c in data.topCategories)
              pw.Text(
                '${c.name}: ${fmt(c.total)}',
                style: pw.TextStyle(font: base, fontSize: 10),
              ),
            if (data.budgetMillimes != null) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                '${fmt(data.budgetSpentMillimes ?? 0)} / ${fmt(data.budgetMillimes!)}',
                style: pw.TextStyle(font: base, fontSize: 10),
              ),
              if (data.budgetRemaining != null)
                pw.Text(
                  fmt(data.budgetRemaining!),
                  style: pw.TextStyle(font: base, fontSize: 10),
                ),
            ],
          ],
        ),
      ),
    );
    return doc.save();
  }
}
