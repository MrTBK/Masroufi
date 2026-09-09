import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../app/providers.dart';
import '../../core/export/monthly_statement.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'package:flutter/services.dart';

/// Year-in-review shareable card (Track 7, no schema, offline).
///
/// Pure data builder ([YearReviewData]) is unit-tested (not pixels).
/// The card itself is a [RepaintBoundary] so it can be screenshotted/
/// shared offline; the Share button reuses the PDF pipeline (yearly
/// totals as 12 monthly statements would be heavy, so we share a
/// one-page summary PDF built from the same data).
class YearReviewData {
  final int year;
  final int incomeMillimes;
  final int expenseMillimes;
  final int txnCount;
  final String topCategory;
  final int topCategoryMillimes;
  const YearReviewData({
    required this.year,
    required this.incomeMillimes,
    required this.expenseMillimes,
    required this.txnCount,
    required this.topCategory,
    required this.topCategoryMillimes,
  });
  int get netMillimes => incomeMillimes - expenseMillimes;

  /// Pure assembly from repo outputs (sums + by-category + count).
  static YearReviewData build({
    required int year,
    required int incomeMillimes,
    required int expenseMillimes,
    required int txnCount,
    Map<String?, int> byCategory = const {},
    Map<String, String> names = const {},
  }) {
    String top = '—';
    var topV = 0;
    for (final e in byCategory.entries) {
      if (e.value > topV) {
        topV = e.value;
        final k = e.key;
        top = k == null ? '—' : (names[k] ?? k);
      }
    }
    return YearReviewData(
      year: year,
      incomeMillimes: incomeMillimes,
      expenseMillimes: expenseMillimes,
      txnCount: txnCount,
      topCategory: top,
      topCategoryMillimes: topV,
    );
  }
}

class YearReviewCard extends ConsumerWidget {
  final YearReviewData data;
  const YearReviewCard({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return RepaintBoundary(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${Strings.get(lang, 'yearReview')} • ${data.year}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            MoneyText(
              millimes: data.expenseMillimes,
              lang: lang,
              type: 'neutral',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${Strings.get(lang, 'income')}: '
              '${Money.inline(data.incomeMillimes, lang: lang)} • '
              '${data.txnCount} txn • ${data.topCategory}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: Text(Strings.get(lang, 'share')),
              onPressed: () => _share(context, ref, lang),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    String lang,
  ) async {
    // Offline share: one-page PDF from the yearly totals (reuses the
    // monthly statement renderer with December as the label month and
    // the yearly sums as the payload — documented approximation).
    final payload = MonthlyStatementBuilder.build(
      year: data.year,
      month: 12,
      incomeMillimes: data.incomeMillimes,
      expenseMillimes: data.expenseMillimes,
      txnCount: data.txnCount,
      byCategory: {data.topCategory: data.topCategoryMillimes},
      categoryNames: {data.topCategory: data.topCategory},
    );
    ByteData? font;
    try {
      font = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    } catch (_) {}
    final bytes = await MonthlyStatementBuilder.buildPdf(
      data: payload,
      lang: lang,
      arabicFont: font,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'masroufi_year_${data.year}.pdf',
    );
  }
}
