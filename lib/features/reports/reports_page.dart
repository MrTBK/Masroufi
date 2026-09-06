import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';

/// MVP reports: spending by category, income vs expenses, monthly total.
/// Simple bar-style visuals, no chart dependency.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final db = ref.watch(appDbProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'reports'))),
      body: FutureBuilder(
        future: Future.wait([
          db.monthSums(now.year, now.month),
          db.expenseByCategory(now.year, now.month),
          catsRepo.all(),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final sums = snap.data![0] as ({int income, int expense});
          final byCat = snap.data![1] as Map<String?, int>;
          final cats = snap.data![2] as List<Category>;
          final entries = byCat.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final maxV = entries.isEmpty ? 0 : entries.first.value.toDouble();
          final total = sums.income + sums.expense;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                Strings.get(lang, 'monthlyTotal'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    Money.format(sums.expense, lang: lang),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                Strings.get(lang, 'incomeVsExpense'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _barRow(
                context,
                Strings.get(lang, 'income'),
                sums.income,
                total,
                Colors.green,
                lang,
              ),
              _barRow(
                context,
                Strings.get(lang, 'expense'),
                sums.expense,
                total,
                Colors.deepOrange,
                lang,
              ),
              const SizedBox(height: 16),
              Text(
                Strings.get(lang, 'byCategory'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                EmptyState(
                  title: Strings.get(lang, 'noTransactions'),
                  body: '',
                  icon: Icons.bar_chart,
                ),
              for (final e in entries)
                _barRow(
                  context,
                  _catName(lang, cats, e.key),
                  e.value,
                  maxV.toInt(),
                  Theme.of(context).colorScheme.primary,
                  lang,
                ),
            ],
          );
        },
      ),
    );
  }

  String _catName(String lang, List<Category> cats, String? id) {
    if (id == null) return '—';
    return cats
            .where((c) => c.id == id)
            .map((c) => Strings.categoryName(lang, c.nameKey, c.customName))
            .firstOrNull ??
        '—';
  }

  Widget _barRow(
    BuildContext context,
    String label,
    int value,
    int max,
    Color color,
    String lang,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(Money.format(value, lang: lang)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: max <= 0 ? 0 : value / max,
            minHeight: 8,
            color: color,
          ),
        ],
      ),
    );
  }
}
