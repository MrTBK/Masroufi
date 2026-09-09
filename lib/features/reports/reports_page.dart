import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/export/monthly_statement.dart';
import '../../core/wealth/net_worth.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/repositories/transactions_repo.dart';
import 'year_review_card.dart';

/// Reports (§16): monthly total, income vs expenses, by-category, monthly
/// comparison, 6-month trend, budget adherence, savings progress.
/// Custom widgets only — no chart library.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final db = ref.watch(appDbProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);
    final catBudgets = ref.watch(categoryBudgetsRepoProvider);
    final budgets = ref.watch(budgetsRepoProvider);
    final savings = ref.watch(savingsRepoProvider);
    final now = DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.get(lang, 'reports')),
        actions: [
          IconButton(
            tooltip: Strings.get(lang, 'exportPdf'),
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _exportPdf(context, ref, lang),
          ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([
          db.monthSums(now.year, now.month),
          db.expenseByCategory(now.year, now.month),
          catsRepo.all(),
          Future.wait(months.map((m) => db.monthSums(m.year, m.month))),
          budgets.getMonth(now.year, now.month),
          budgets.spent(now.year, now.month),
          catBudgets.forMonth(now.year, now.month),
          savings.all(includeArchived: false),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final sums = snap.data![0] as ({int income, int expense});
          final cats = snap.data![2] as List<Category>;
          final byId = {for (final c in cats) c.id: c};
          final byCat = CategoryHierarchy.rollUp(
            snap.data![1] as Map<String?, int>,
            cats,
          );
          final trend = snap.data![3] as List<({int income, int expense})>;
          final budget = snap.data![4] as Budget?;
          final spent = snap.data![5] as int;
          final catB = snap.data![6] as List<CategoryBudget>;
          final goals = snap.data![7] as List<SavingsGoal>;
          final entries = byCat.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final total = sums.income + sums.expense;
          final maxTrend = [for (final t in trend) t.expense]
              .fold<int>(0, (a, b) => a > b ? a : b);

          String catName(String? id) {
            if (id == null) return '—';
            final c = byId[id];
            if (c == null) return '—';
            return CategoryHierarchy.displayName(lang, c, byId);
          }

          String catIcon(String? id) {
            if (id == null) return 'other';
            return cats
                    .where((c) => c.id == id)
                    .map((c) => c.icon)
                    .firstOrNull ??
                'other';
          }

          // Grouped by parent: rolled-up parent rows expand to children.
          final childEntries = <String, List<MapEntry<String?, int>>>{};
          for (final e in entries) {
            final c = e.key == null ? null : byId[e.key];
            final pid = c?.parentId;
            if (pid != null && byId.containsKey(pid)) {
              (childEntries[pid] ??= []).add(e);
            }
          }

          Widget byCatRow(String? id, int value) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  CategoryAvatar(
                    iconKey: catIcon(id),
                    radius: 16,
                    semanticLabel: catName(id),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      catName(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  MoneyText(millimes: value, lang: lang, type: 'neutral'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionHeader(title: Strings.get(lang, 'monthlyTotal')),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: MoneyText(
                  millimes: sums.expense,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              SectionHeader(title: Strings.get(lang, 'incomeVsExpense')),
              AppCard(
                child: Column(
                  children: [
                    _barRow(
                      context,
                      Strings.get(lang, 'income'),
                      sums.income,
                      total,
                      AppColors.income,
                      lang,
                    ),
                    _barRow(
                      context,
                      Strings.get(lang, 'expense'),
                      sums.expense,
                      total,
                      AppColors.expense,
                      lang,
                    ),
                  ],
                ),
              ),
              SectionHeader(title: Strings.get(lang, 'byCategory')),
              AppCard(
                child: entries.isEmpty
                    ? Text(
                        Strings.get(lang, 'noTransactions'),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : Column(
                        children: [
                          for (final e in entries)
                            if (byId[e.key]?.parentId == null ||
                                !byId.containsKey(byId[e.key]!.parentId))
                              if ((childEntries[e.key] ?? const []).isEmpty)
                                byCatRow(e.key, e.value)
                              else
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding:
                                      const EdgeInsetsDirectional.only(
                                        start: 20,
                                      ),
                                  leading: CategoryAvatar(
                                    iconKey: catIcon(e.key),
                                    radius: 16,
                                    semanticLabel: catName(e.key),
                                  ),
                                  title: Text(
                                    catName(e.key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: MoneyText(
                                    millimes: e.value,
                                    lang: lang,
                                    type: 'neutral',
                                  ),
                                  children: [
                                    for (final k in childEntries[e.key]!)
                                      byCatRow(k.key, k.value),
                                  ],
                                ),
                        ],
                      ),
              ),
              SectionHeader(title: Strings.get(lang, 'trend')),
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < months.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            children: [
                              MoneyText(
                                millimes: trend[i].expense ~/ 1000 * 1000,
                                lang: lang,
                                type: 'neutral',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontSize: 10),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height:
                                    24 +
                                    (maxTrend <= 0
                                        ? 0.0
                                        : 76 * trend[i].expense / maxTrend),
                                decoration: BoxDecoration(
                                  color: i == months.length - 1
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${months[i].month}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (budget != null || catB.isNotEmpty) ...[
                SectionHeader(title: Strings.get(lang, 'budgetAdherence')),
                if (budget != null)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Strings.get(lang, 'budget'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        BudgetBar(
                          spentMillimes: spent,
                          totalMillimes: budget.amountMillimes,
                          lang: lang,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                for (final cb in catB)
                  FutureBuilder(
                    future: catBudgets.status(
                      cb.categoryId,
                      now.year,
                      now.month,
                    ),
                    builder: (context, st) {
                      final s =
                          st.data ??
                          (spent: 0, remaining: cb.amountMillimes, pct: 0.0);
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  catName(cb.categoryId),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                BudgetBar(
                                  spentMillimes: s.spent,
                                  totalMillimes: cb.amountMillimes,
                                  lang: lang,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
              ],
              if (goals.isNotEmpty) ...[
                SectionHeader(title: Strings.get(lang, 'savingsGoals')),
                for (final g in goals)
                  FutureBuilder<int>(
                    future: savings.currentAmount(g.id),
                    builder: (context, amt) {
                      final cur = amt.data ?? 0;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                BudgetBar(
                                  spentMillimes: cur,
                                  totalMillimes: g.targetMillimes,
                                  lang: lang,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
              ],
              _NetWorthSection(db: db, lang: lang),
              _YearReviewSection(lang: lang),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  /// Monthly PDF export (Track 2): builds the statement from the same
  /// [AnalyticsRepo]/budget sources as the screen, renders via
  /// [MonthlyStatementBuilder] with the bundled Amiri font for Arabic
  /// shaping, then opens the platform share sheet. No schema, no
  /// permissions, offline.
  Future<void> _exportPdf(
    BuildContext context,
    WidgetRef ref,
    String lang,
  ) async {
    final db = ref.read(appDbProvider);
    final catsRepo = ref.read(categoriesRepoProvider);
    final budgets = ref.read(budgetsRepoProvider);
    final txns = ref.read(transactionsRepoProvider);
    final now = DateTime.now();
    final range = (start: DateTime(now.year, now.month, 1), end: now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1));
    try {
      final sums = await db.monthSums(now.year, now.month);
      final byCat = await db.expenseByCategory(now.year, now.month);
      final cats = await catsRepo.all();
      final byId = {for (final c in cats) c.id: c};
      final names = {
        for (final e in byCat.keys.whereType<String>())
          e: byId[e] == null
              ? e
              : CategoryHierarchy.displayName(lang, byId[e]!, byId),
      };
      final monthTxns = await txns.list(
        TxnFilter(from: range.start, to: range.end, limit: 100000),
      );
      final budget = await budgets.getMonth(now.year, now.month);
      final spent = await budgets.spent(now.year, now.month);
      final data = MonthlyStatementBuilder.build(
        year: now.year,
        month: now.month,
        incomeMillimes: sums.income,
        expenseMillimes: sums.expense,
        txnCount: monthTxns.length,
        byCategory: byCat,
        categoryNames: names,
        budgetMillimes: budget?.amountMillimes,
        budgetSpentMillimes: budget == null ? null : spent,
      );
      ByteData? font;
      try {
        font = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      } catch (_) {
        font = null;
      }
      final bytes = await MonthlyStatementBuilder.buildPdf(
        data: data,
        lang: lang,
        arabicFont: font,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'masroufi_${now.year}-${now.month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.get(lang, 'invalidBackup'))),
        );
      }
    }
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              MoneyText(millimes: value, lang: lang, type: 'neutral'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: max <= 0 ? 0 : value / max,
            minHeight: 8,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            color: color,
          ),
        ],
      ),
    );
  }
}

/// Net-worth trend mini-chart (Track 7): documented formula in
/// [NetWorth], custom bars (no chart dep), never relabeled as anything
/// else. Data-tested, not pixel-tested.
class _NetWorthSection extends StatelessWidget {
  final AppDb db;
  final String lang;
  const _NetWorthSection({required this.db, required this.lang});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: NetWorth.trend(db: db, now: DateTime.now()),
      builder: (context, snap) {
        final trend = snap.data ?? const <WorthPoint>[];
        if (trend.isEmpty) return const SizedBox.shrink();
        final maxV = trend.map((p) => p.worth).fold(0, (a, b) => a > b ? a : b);
        final minV = trend.map((p) => p.worth).fold(maxV, (a, b) => a < b ? a : b);
        final span = (maxV - minV) <= 0 ? 1 : (maxV - minV);
        return Column(
          children: [
            SectionHeader(title: Strings.get(lang, 'netWorth')),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyText(
                    millimes: trend.last.worth,
                    lang: lang,
                    type: 'neutral',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final p in trend)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              children: [
                                Container(
                                  height:
                                      12 + 64 * (p.worth - minV) / span,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${p.month}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Strings.get(lang, 'netWorthNote'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Year-in-review loader (Track 7): yearly aggregates → [YearReviewCard]
/// (RepaintBoundary, offline share). Data-tested via [YearReviewData].
class _YearReviewSection extends ConsumerWidget {
  final String lang;
  const _YearReviewSection({required this.lang});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsRepoProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);
    final txns = ref.watch(transactionsRepoProvider);
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    final end = DateTime(now.year + 1, 1, 1);
    return FutureBuilder(
      future: Future.wait([
        analytics.incomeTotal(start, end),
        analytics.expenseTotal(start, end),
        analytics.expenseByCategory(start, end),
        catsRepo.all(),
        txns.list(TxnFilter(from: start, to: end, limit: 100000)),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final income = snap.data![0] as int;
        final expense = snap.data![1] as int;
        final byCat = snap.data![2] as Map<String?, int>;
        final cats = snap.data![3] as List<Category>;
        final list = snap.data![4] as List<Transaction>;
        if (income <= 0 && expense <= 0) return const SizedBox.shrink();
        final byId = {for (final c in cats) c.id: c};
        final names = {
          for (final e in byCat.keys.whereType<String>())
            e: byId[e] == null
                ? e
                : CategoryHierarchy.displayName(lang, byId[e]!, byId),
        };
        final data = YearReviewData.build(
          year: now.year,
          incomeMillimes: income,
          expenseMillimes: expense,
          txnCount: list.length,
          byCategory: byCat,
          names: names,
        );
        return Column(
          children: [
            SectionHeader(title: Strings.get(lang, 'yearReview')),
            YearReviewCard(data: data),
          ],
        );
      },
    );
  }
}
