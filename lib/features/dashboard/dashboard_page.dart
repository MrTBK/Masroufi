import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hide intl's own TextDirection class (shadows Flutter's enum).
import 'package:intl/intl.dart' hide TextDirection;

import '../../app/providers.dart';
import '../../core/analytics/bi_scope.dart';
import '../../core/analytics/forecast.dart';
import '../../core/analytics/insights.dart';
import '../../core/analytics/kpi.dart';
import '../../core/analytics/periods.dart';
import '../../core/analytics/stats.dart';
import '../../core/analytics/summary.dart';
import '../../core/money/money.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/donut_chart.dart';
import '../../core/widgets/masroufi_nav.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/repositories/analytics_repo.dart';
import '../../data/repositories/transactions_repo.dart';
import '../transactions/txn_sheets.dart';

/// Dashboard period ids (min spec: thisWeek|lastWeek|thisMonth|lastMonth,
/// plus inherited last3Months|year for trend context).
const dashPeriods = [
  'thisWeek',
  'lastWeek',
  'thisMonth',
  'lastMonth',
  'last3Months',
  'year',
];

/// Half-open [start, end) range backing a dashboard period id.
({DateTime start, DateTime end}) dashRangeFor(
  String period,
  DateTime now,
  String weekStart,
) {
  final p = normalizedDashPeriod(period);
  switch (p) {
    case 'thisWeek':
      return Periods.week(now, weekStart);
    case 'lastWeek':
      return Periods.lastWeek(now, weekStart);
    case 'lastMonth':
      return Periods.lastMonth(now);
    case 'last3Months':
      return Periods.last3Months(now);
    case 'year':
      return Periods.year(now);
    case 'thisMonth':
    default:
      return Periods.month(now);
  }
}

/// Localized label key for a dashboard period id.
String dashPeriodLabelKey(String period) {
  switch (normalizedDashPeriod(period)) {
    case 'thisWeek':
      return 'thisWeek';
    case 'lastWeek':
      return 'lastWeek';
    case 'lastMonth':
      return 'lastMonth';
    case 'last3Months':
      return 'last3Months';
    case 'year':
      return 'thisYear';
    case 'thisMonth':
    default:
      return 'thisMonth';
  }
}

class _DashData {
  final int total;
  final List<Wallet> wallets;
  final List<Category> cats;
  final bool hasTxns;
  // Deterministic month-over-month insight lines (current vs previous
  // calendar month; empty when data is insufficient — never noise).
  final List<String> insightsLines;
  // Upcoming recurring occurrences (compact strip, at most 3).
  final List<({RecurringRule rule, DateTime date})> upcoming;
  // Factual health lines (check vs warning icons, never scores).
  final List<({String text, bool warn})> healthLines;
  // Current-month spending calendar inputs.
  final DateTime calendarMonth;
  final Map<DateTime, int> calendarDays;
  _DashData({
    required this.total,
    required this.insightsLines,
    required this.upcoming,
    required this.healthLines,
    required this.calendarMonth,
    required this.calendarDays,
    required this.wallets,
    required this.cats,
    required this.hasTxns,
  });
}

final _dashProvider = FutureProvider<_DashData>((ref) async {
  ref.watch(refreshTickProvider);
  final now = DateTime.now();
  final walletsRepo = ref.watch(walletsRepoProvider);
  final analytics = ref.watch(analyticsRepoProvider);
  final catsRepo = ref.watch(categoriesRepoProvider);
  final txns = ref.watch(transactionsRepoProvider);
  final summary = FinancialSummaryService(
    analytics: analytics,
    wallets: walletsRepo,
  );
  final total = await summary.totalMoney();
  final wallets = await walletsRepo.all(includeArchived: false);
  final cats = await catsRepo.all();
  final hasTxns = (await txns.list(const TxnFilter(limit: 1))).isNotEmpty;
  final lang = ref.watch(languageProvider);
  final analysis = await _monthAnalysis(
    analytics: analytics,
    cats: cats,
    now: now,
    lang: lang,
  );
  final upcoming = await ref
      .watch(recurringRepoProvider)
      .upcoming(days: 30, limit: 3);
  final budget = await ref
      .watch(budgetsRepoProvider)
      .getMonth(now.year, now.month);
  final daysInMonth = Periods.daysInMonth(now.year, now.month);
  final healthLines = Insights.buildHealth(
    budgetMillimes: budget?.amountMillimes,
    monthSpentMillimes: analysis.curExp,
    secondTopCat: analysis.secondTop,
    daysLeft: (daysInMonth - now.day + 1).clamp(1, daysInMonth),
    lang: lang,
  );
  // Track 3 pager: calendar follows calMonthProvider (chevrons),
  // defaulting to the current month. Clamped to a sane window.
  var calMonth = ref.watch(calMonthProvider);
  calMonth = DateTime(calMonth.year, calMonth.month, 1);
  final calNext = calMonth.month == 12
      ? DateTime(calMonth.year + 1, 1, 1)
      : DateTime(calMonth.year, calMonth.month + 1, 1);
  final calendarDays = await analytics.dailyExpenseTotals(calMonth, calNext);
  return _DashData(
    total: total,
    insightsLines: analysis.lines,
    upcoming: upcoming,
    healthLines: healthLines,
    calendarMonth: calMonth,
    calendarDays: calendarDays,
    wallets: wallets,
    cats: cats,
    hasTxns: hasTxns,
  );
});

String _catName(String lang, List<Category> cats, String? id) {
  if (id == null) return Strings.get(lang, 'uncategorized');
  for (final c in cats) {
    if (c.id == id) return Strings.categoryName(lang, c.nameKey, c.customName);
  }
  return '—';
}

String? _catIcon(List<Category> cats, String? id) {
  if (id == null) return null;
  for (final c in cats) {
    if (c.id == id) return c.icon;
  }
  return null;
}

/// Deterministic month analysis: always the current vs previous CALENDAR
/// month (analysis-stable regardless of the selected dashboard period).
/// One batched read feeds the insight lines, the MoM widget, the second
/// rank (health facts) and the calendar-independent totals.
Future<
  ({
    List<String> lines,
    int curExp,
    int prevExp,
    int? momPct,
    String? secondTop,
  })
>
_monthAnalysis({
  required AnalyticsRepo analytics,
  required List<Category> cats,
  required DateTime now,
  required String lang,
}) async {
  final cur = Periods.month(now);
  final prev = Periods.lastMonth(now);
  final results = await Future.wait([
    analytics.expenseTotal(cur.start, cur.end),
    analytics.expenseTotal(prev.start, prev.end),
    analytics.incomeTotal(cur.start, cur.end),
    analytics.incomeTotal(prev.start, prev.end),
    analytics.expenseByCategory(cur.start, cur.end),
    analytics.expenseByPriority(cur.start, cur.end),
  ]);
  final curExp = results[0] as int;
  final prevExp = results[1] as int;
  final curInc = results[2] as int;
  final prevInc = results[3] as int;
  final byCat = results[4] as Map<String?, int>;
  final byPri = results[5] as Map<String, int>;
  if (curExp <= 0) {
    return (
      lines: const <String>[],
      curExp: curExp,
      prevExp: prevExp,
      momPct: null,
      secondTop: null,
    );
  }
  final byId = {for (final c in cats) c.id: c};
  final rolled = CategoryHierarchy.rollUp(byCat, cats);
  final primaries =
      rolled.entries
          .where((e) => e.value > 0)
          .where((e) => e.key == null || byId[e.key]?.parentId == null)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final topName = primaries.isEmpty
      ? null
      : _catName(lang, cats, primaries.first.key);
  final secondTop = primaries.length < 2
      ? null
      : _catName(lang, cats, primaries[1].key);
  final mom = AnalyticsStats.monthOverMonth(current: curExp, previous: prevExp);
  final elapsed = Periods.elapsedDays(cur.start, cur.end, now);
  return (
    lines: Insights.buildInsights(
      currentExpense: curExp,
      previousExpense: prevExp,
      topCatName: topName,
      funSharePct: AnalyticsStats.sharePct(
        part: byPri['fun'] ?? 0,
        total: curExp,
      ),
      incomeMoM: AnalyticsStats.monthOverMonth(
        current: curInc,
        previous: prevInc,
      ),
      dailyAvgFormatted: Money.format(curExp ~/ elapsed, lang: lang),
      lang: lang,
    ),
    curExp: curExp,
    prevExp: prevExp,
    momPct: mom?.pct,
    secondTop: secondTop,
  );
}

/// Pure calendar grid for a month: weeks × 7 day cells (null = padding),
/// weeks starting on [weekStartWeekday] (DateTime.monday..sunday, from
/// settings). Unit-tested; the widget only renders this structure.
List<List<DateTime?>> buildCalendarWeeks(DateTime month, int weekStartWeekday) {
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = Periods.daysInMonth(month.year, month.month);
  final lead = (first.weekday - weekStartWeekday + 7) % 7;
  final cells = <DateTime?>[
    for (var i = 0; i < lead; i++) null,
    for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [for (var w = 0; w < cells.length; w += 7) cells.sublist(w, w + 7)];
}

/// Financial-analysis dashboard (spec §8-14): totals → donut →
/// top categories → averages → money in/out. Not a transaction list.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final async = ref.watch(_dashProvider);
    final bi = ref.watch(biSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: HomeTitle(text: Brand.nameFor(lang), lang: lang),
        actions: [
          IconButton(
            tooltip: Strings.get(lang, 'settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(_dashProvider),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_dashProvider);
            ref.invalidate(biSnapshotProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              HomeTopSwitch(
                showTransactions: false,
                lang: lang,
                onTransactions: () => context.go('/'),
                onDashboard: () {},
                onSettings: () => context.push('/settings'),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Account total is global (never filtered); everything
              // below the filter bar reads the BI snapshot.
              _totals(context, ref, lang, d),
              const SizedBox(height: AppSpacing.lg),
              _BiFilterBar(lang: lang),
              const SizedBox(height: AppSpacing.md),
              bi.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  message: '$e',
                  onRetry: () => ref.invalidate(biSnapshotProvider),
                ),
                data: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!d.hasTxns)
                      EmptyState(
                        title: Strings.get(lang, 'welcomeTitle'),
                        body: Strings.get(lang, 'welcomeBody'),
                        icon: Icons.pie_chart,
                      )
                    else ...[
                      _KpiGrid(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _ForecastCard(lang: lang, s: s),
                      _donutSection(context, lang, s),
                      const SizedBox(height: AppSpacing.lg),
                      _BiTypeScope(
                        type: ref.watch(biFilterProvider).type,
                        child: _DrillTree(lang: lang, s: s),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _WalletSection(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _BiTrend(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _moneyInOut(context, lang, s),
                      const SizedBox(height: AppSpacing.lg),
                      _BudgetVsActual(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _HealthSection(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _insights(context, lang, d),
                      _Movers(lang: lang, s: s),
                      const SizedBox(height: AppSpacing.lg),
                      _upcoming(context, lang, d),
                      const SizedBox(height: AppSpacing.lg),
                      _calendar(context, ref, lang, d),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Only the global privacy switch masks the total now: per-wallet
  /// hiding EXCLUDES the wallet from the displayed total (see
  /// `WalletsRepo.visibleBalance`), so nothing can leak by subtraction.
  bool _totalMasked(WidgetRef ref) => ref.watch(hideBalancesProvider);

  /// Account total hero (global by design: your money is a fact, not a
  /// filter result). Period figures moved to the KPI grid below.
  Widget _totals(
    BuildContext context,
    WidgetRef ref,
    String lang,
    _DashData d,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final masked = _totalMasked(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Strings.get(lang, 'totalMoney'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        masked
            ? HiddenBalance(
                semanticLabel: Strings.get(lang, 'hiddenBalance'),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              )
            : MoneyText(
                millimes: d.total,
                lang: lang,
                type: 'neutral',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
      ],
    );
  }

  Widget _donutSection(BuildContext context, String lang, BiSnapshot s) {
    final byId = {for (final c in s.cats) c.id: c};
    final rolled = CategoryHierarchy.rollUp(s.byCategory, s.cats);
    final entries =
        rolled.entries
            .where((e) => e.value > 0)
            .where((e) => e.key == null || byId[e.key]?.parentId == null)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final slices = [
      for (var i = 0; i < top.length; i++)
        DonutSlice(
          id: top[i].key,
          label: _catName(lang, s.cats, top[i].key),
          iconKey: _catIcon(s.cats, top[i].key),
          value: top[i].value,
          color: DonutPalette.of(context)[i % DonutPalette.colors.length],
        ),
    ];
    final growth = s.growth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'spending')),
        // Scope comparison (whole-percent, int-only math): this scope
        // vs the previous equal-length range. Own template (never the
        // calendar-month MoM sentence: wording must stay true on week,
        // day, and year scopes, and must not duplicate the insights
        // section on month scopes).
        if (growth != null && growth.pct != 0 && s.expense > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  growth.pct < 0 ? Icons.trending_down : Icons.trending_up,
                  size: 18,
                  color: growth.pct < 0 ? AppColors.income : AppColors.expense,
                  semanticLabel: '${growth.pct}%',
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    Strings.tpl(lang, 'insScopeGrowth', {
                      'v': '${growth.pct > 0 ? '+' : ''}${growth.pct}%',
                    }),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (s.yoyExpense != null && s.yoyExpense! > 0 && s.expense > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: Strings.get(lang, 'yoy'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${Money.inline(s.yoyExpense!, lang: lang)} '
                    '${Strings.get(lang, 'yoy')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Center(
          child: DonutChart(
            slices: slices,
            totalMillimes: s.expense,
            lang: lang,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                CategoryAvatar(
                  iconKey: s.iconKey,
                  radius: 16,
                  semanticLabel: s.label,
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MoneyText(
                  millimes: s.value,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _moneyInOut(BuildContext context, String lang, BiSnapshot s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'moneyInOut')),
        MoneyInOutBars(
          incomeMillimes: s.income,
          expenseMillimes: s.expense,
          lang: lang,
        ),
      ],
    );
  }

  /// Deterministic insight + health lines: localized sentences, never
  /// LLM output, hidden when data is insufficient. Health facts use
  /// check/warning icons (never an invented score).
  Widget _insights(BuildContext context, String lang, _DashData d) {
    if (d.insightsLines.isEmpty && d.healthLines.isEmpty) {
      return const SizedBox.shrink();
    }
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'insights')),
        for (final line in d.insightsLines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: variant,
                    semanticLabel: line,
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(child: Text(line)),
              ],
            ),
          ),
        for (final h in d.healthLines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    h.warn ? Icons.warning_amber : Icons.check_circle_outline,
                    size: 18,
                    color: h.warn
                        ? Theme.of(context).colorScheme.error
                        : AppColors.income,
                    semanticLabel: h.text,
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(child: Text(h.text)),
              ],
            ),
          ),
      ],
    );
  }

  /// Upcoming recurring occurrences (compact secondary strip): next 3
  /// by date with wallet + amount; tap opens the recurring manager.
  Widget _upcoming(BuildContext context, String lang, _DashData d) {
    if (d.upcoming.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final byId = {for (final c in d.cats) c.id: c};
    String walletName(String id) =>
        d.wallets.where((w) => w.id == id).map((w) => w.name).firstOrNull ??
        '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: Strings.get(lang, 'upcoming'),
          actionLabel: Strings.get(lang, 'recurring'),
          onAction: () => context.push('/settings/recurring'),
        ),
        for (var i = 0; i < d.upcoming.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 68),
          Builder(
            builder: (context) {
              final u = d.upcoming[i];
              final cat = u.rule.categoryId == null
                  ? null
                  : byId[u.rule.categoryId];
              final title = u.rule.note.isNotEmpty
                  ? u.rule.note
                  : cat == null
                  ? Strings.get(
                      lang,
                      u.rule.type == 'income' ? 'income' : 'expense',
                    )
                  : Strings.categoryName(lang, cat.nameKey, cat.customName);
              return TransactionTile(
                iconKey: cat?.icon,
                title: title,
                subtitle:
                    '${walletName(u.rule.walletId)} · ${_upcomingDay(u.date, now, lang)}',
                millimes: u.rule.amountMillimes,
                lang: lang,
                type: u.rule.type,
                onTap: () => context.push('/settings/recurring'),
              );
            },
          ),
        ],
      ],
    );
  }

  /// "Tomorrow" / weekday label for an upcoming date (locale-aware).
  String _upcomingDay(DateTime date, DateTime now, String lang) {
    final diff = Periods.dayStart(date)
        .difference(Periods.dayStart(now))
        .inDays;
    if (diff <= 0) return Strings.get(lang, 'today');
    if (diff == 1) return Strings.get(lang, 'tomorrow');
    try {
      final locale = switch (lang) {
        'ar' => 'ar',
        'fr' => 'fr',
        _ => 'en',
      };
      return DateFormat('d MMMM', locale).format(date);
    } catch (_) {
      return '${date.month}/${date.day}';
    }
  }

  /// Secondary spending calendar (§33): current month grid with subtle
  /// per-day intensity; tap a day for its transactions. Deliberately
  /// compact and kept off the Transactions page.
  Widget _calendar(
    BuildContext context,
    WidgetRef ref,
    String lang,
    _DashData d,
  ) {
    final weekStart = ref.watch(weekStartProvider);
    final startDay = switch (weekStart) {
      'sunday' => DateTime.sunday,
      'saturday' => DateTime.saturday,
      _ => DateTime.monday,
    };
    final weeks = buildCalendarWeeks(d.calendarMonth, startDay);
    String monthTitle() {
      try {
        final locale = switch (lang) {
          'ar' => 'ar',
          'fr' => 'fr',
          _ => 'en',
        };
        return DateFormat('MMMM yyyy', locale).format(d.calendarMonth);
      } catch (_) {
        return '${d.calendarMonth.month}/${d.calendarMonth.year}';
      }
    }

    String weekdayLabel(int column) {
      // column 0..6 → weekday int honoring the week-start setting.
      final weekday = ((startDay - 1 + column) % 7) + 1;
      try {
        final locale = switch (lang) {
          'ar' => 'ar',
          'fr' => 'fr',
          _ => 'en',
        };
        // 2024-01-01 was a Monday: sample any matching weekday.
        final sample = DateTime(2024, 1, 1).add(Duration(days: weekday - 1));
        return DateFormat.E(locale).format(sample);
      } catch (_) {
        return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
      }
    }

    final maxV = d.calendarDays.values.fold(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: '${Strings.get(lang, 'calendar')} • ${monthTitle()}',
              ),
            ),
            IconButton(
              tooltip: Strings.get(lang, 'calPrev'),
              // Pager chevrons mirror: previous points toward the
              // reading-start side in both directions.
              icon: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_right
                    : Icons.chevron_left,
              ),
              onPressed: () {
                final m = ref.read(calMonthProvider);
                ref.read(calMonthProvider.notifier).state = DateTime(
                  m.month == 1 ? m.year - 1 : m.year,
                  m.month == 1 ? 12 : m.month - 1,
                  1,
                );
              },
            ),
            IconButton(
              tooltip: Strings.get(lang, 'calNext'),
              icon: Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
              ),
              onPressed: () {
                final m = ref.read(calMonthProvider);
                ref.read(calMonthProvider.notifier).state = DateTime(
                  m.month == 12 ? m.year + 1 : m.year,
                  m.month == 12 ? 1 : m.month + 1,
                  1,
                );
              },
            ),
          ],
        ),
        Row(
          children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdayLabel(c),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final week in weeks)
          Row(
            children: [
              for (final day in week)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: day == null
                        ? const SizedBox.shrink()
                        : Builder(
                            builder: (context) {
                              final v =
                                  d.calendarDays[Periods.dayStart(day)] ?? 0;
                              final frac = maxV <= 0
                                  ? 0.0
                                  : (v / maxV).clamp(0.0, 1.0);
                              final isToday =
                                  Periods.dayStart(day) ==
                                  Periods.dayStart(DateTime.now());
                              return InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                onTap: v <= 0
                                    ? null
                                    : () => _daySheet(
                                        context,
                                        ref,
                                        lang,
                                        d,
                                        Periods.dayStart(day),
                                        v,
                                      ),
                                child: Container(
                                  margin: const EdgeInsets.all(AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    color: v <= 0
                                        ? Colors.transparent
                                        : scheme.primaryContainer.withValues(
                                            alpha: 0.35 + 0.65 * frac,
                                          ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                    border: isToday
                                        ? Border.all(color: scheme.primary)
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${day.day}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: isToday
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// One day's transactions (from the calendar): total + compact rows,
  /// tap a row for the full detail sheet.
  Future<void> _daySheet(
    BuildContext context,
    WidgetRef ref,
    String lang,
    _DashData d,
    DateTime day,
    int dayTotal,
  ) {
    final txnsRepo = ref.read(transactionsRepoProvider);
    final byId = {for (final c in d.cats) c.id: c};
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: FutureBuilder(
            future: txnsRepo.list(
              TxnFilter(
                from: day,
                to: day.add(const Duration(days: 1)),
                limit: 200,
              ),
            ),
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dayGroupHeader(day, DateTime.now(), lang),
                          style: Theme.of(c).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      MoneyText(
                        millimes: dayTotal,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(c).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 68),
                          Builder(
                            builder: (c) {
                              final t = list[i];
                              return TransactionTile(
                                iconKey: t.type == 'transfer'
                                    ? 'transfer'
                                    : byId[t.categoryId]?.icon,
                                title: txnTitle(lang, t, d.wallets, byId),
                                subtitle: txnTime(t.occurredAt),
                                millimes: t.amountMillimes,
                                lang: lang,
                                type: t.type,
                                onTap: () {
                                  Navigator.pop(c);
                                  showTxnDetail(
                                    context,
                                    ref,
                                    t: t,
                                    wallets: d.wallets,
                                    cats: d.cats,
                                    lang: lang,
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Global BI filter bar: period presets plus wallet, category, and type
/// scoping. Every change rewrites [biFilterProvider], which reloads the
/// single snapshot below, so the whole page recalculates from one point.
/// Option lists load independently (cheap all() reads); selections live
/// in the provider.
class _BiFilterBar extends ConsumerWidget {
  final String lang;
  const _BiFilterBar({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(biFilterProvider);
    final weekStart = ref.watch(weekStartProvider);
    final now = DateTime.now();
    final presets = <String, ({DateTime from, DateTime to})>{
      'today': (
        from: Periods.dayStart(now),
        to: Periods.dayStart(now).add(const Duration(days: 1))
      ),
      'thisWeek': (() {
        final r = Periods.week(now, weekStart);
        return (from: r.start, to: r.end);
      })(),
      'thisMonth': (() {
        final r = Periods.month(now);
        return (from: r.start, to: r.end);
      })(),
      'thisYear': (() {
        final r = Periods.year(now);
        return (from: r.start, to: r.end);
      })(),
    };
    void apply(({DateTime from, DateTime to}) r) {
      ref.read(biFilterProvider.notifier).state = BiFilter(
        from: r.from,
        to: r.to,
        walletIds: filter.walletIds,
        categoryIds: filter.categoryIds,
        type: filter.type,
      );
    }

    // Option lists load once, independently of the snapshot; the bar
    // stays mounted across snapshot reloads.
    return FutureBuilder(
      future: Future.wait([
        ref.watch(walletsRepoProvider).all(includeArchived: false),
        ref.watch(categoriesRepoProvider).all(includeArchived: false),
      ]),
      builder: (context, snap) {
        final wallets = snap.data?[0] as List<Wallet>? ?? const <Wallet>[];
        final cats = snap.data?[1] as List<Category>? ?? const <Category>[];
        final roots = [
          for (final c in cats)
            if (c.parentId == null) c,
        ];
        String catName(String? id) {
          if (id == null) return Strings.get(lang, 'all');
          for (final c in cats) {
            if (c.id == id) {
              return Strings.categoryName(lang, c.nameKey, c.customName);
            }
          }
          return '—';
        }

        String walletName(String? id) {
          if (id == null) return Strings.get(lang, 'all');
          for (final w in wallets) {
            if (w.id == id) return w.name;
          }
          return '—';
        }

        final singleWallet = filter.walletIds.length == 1
            ? filter.walletIds.first
            : null;
        // Category selection stores one id (root or leaf); parents
        // expand to parent-plus-children on load.
        final singleCat = filter.categoryIds?.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in presets.entries) ...[
                    ChoiceChip(
                      label: Text(Strings.get(lang, e.key)),
                      selected:
                          filter.from == e.value.from &&
                          filter.to == e.value.to,
                      onSelected: (_) => apply(e.value),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: singleWallet,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'wallet'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(Strings.get(lang, 'all')),
                      ),
                      for (final w in wallets)
                        DropdownMenuItem(value: w.id, child: Text(w.name)),
                    ],
                    onChanged: (v) =>
                        ref.read(biFilterProvider.notifier).state = BiFilter(
                      from: filter.from,
                      to: filter.to,
                      walletIds: v == null ? const [] : [v],
                      categoryIds: filter.categoryIds,
                      type: filter.type,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: singleCat != null &&
                            roots.any((c) => c.id == singleCat)
                        ? singleCat
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'category'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(Strings.get(lang, 'all')),
                      ),
                      for (final c in roots)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            Strings.categoryName(
                              lang,
                              c.nameKey,
                              c.customName,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        ref.read(biFilterProvider.notifier).state = BiFilter(
                      from: filter.from,
                      to: filter.to,
                      walletIds: filter.walletIds,
                      categoryIds: BiFilter.expandCategory(cats, v),
                      type: filter.type,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Screen-reader mirror of the active scope (icons alone
            // never carry it). Own line so chips never squeeze text.
            Text(
              '${walletName(singleWallet)} • ${catName(singleCat)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in const <String?>[null, 'expense', 'income']) ...[
                    ChoiceChip(
                      label: Text(
                        t == null
                            ? Strings.get(lang, 'all')
                            : Strings.get(lang, t),
                      ),
                      selected: filter.type == t,
                      onSelected: (_) =>
                          ref.read(biFilterProvider.notifier).state = BiFilter(
                        from: filter.from,
                        to: filter.to,
                        walletIds: filter.walletIds,
                        categoryIds: filter.categoryIds,
                        type: t,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Six KPI cells from one snapshot. Null KPIs render an em dash (no
/// data), never a zero masquerading as measurement.
class _KpiGrid extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _KpiGrid({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final effEnd = s.to.isBefore(now) ? s.to : now;
    var elapsed = effEnd.difference(Periods.dayStart(s.from)).inDays;
    if (elapsed < 1) elapsed = 1;
    final avgDaily = s.expense ~/ elapsed;
    final completed = [
      for (final m in s.trend)
        if (m.year < now.year || (m.year == now.year && m.month < now.month))
          m.expense,
    ];
    final avgMonthly = completed.isEmpty
        ? null
        : AnalyticsStats.averageMonthly(completed);
    final net = Kpi.netCashFlow(
      incomeMillimes: s.income,
      expenseMillimes: s.expense,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'insights')),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'income'),
                MoneyText(
                  millimes: s.income,
                  lang: lang,
                  type: 'income',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'expense'),
                MoneyText(
                  millimes: s.expense,
                  lang: lang,
                  type: 'expense',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'netCashFlow'),
                MoneyText(
                  millimes: net,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: net < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'savingsRate'),
                Text(
                  s.savingsRate == null ? '—' : '${s.savingsRate}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: (s.savingsRate ?? 0) < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'avgDaily'),
                MoneyText(
                  millimes: avgDaily,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'monthlyAverage'),
                avgMonthly == null
                    ? Text(
                        '—',
                        style: Theme.of(context).textTheme.titleLarge,
                      )
                    : MoneyText(
                        millimes: avgMonthly,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiCell(BuildContext context, String label, Widget value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          value,
        ],
      ),
    );
  }
}

/// Forecast card: run-rate projection for the current month under the
/// wallet filter, against the overall budget. Hidden when there is
/// nothing to project from.
class _ForecastCard extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _ForecastCard({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final f = Forecast.project(
      spentSoFarMillimes: s.monthSpent,
      now: DateTime.now(),
      budgetMillimes: s.monthBudget,
    );
    if (f == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final over = (f.overrun ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'forecast')),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoneyText(
                millimes: f.projected,
                lang: lang,
                type: 'neutral',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (s.monthBudget != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${Money.inline(s.monthBudget!, lang: lang)} • '
                  '${Strings.get(lang, 'pace')} ${f.pacePct}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: (f.pacePct / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: over ? scheme.error : null,
                ),
                if (f.overrun != null && f.overrun! > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${Strings.get(lang, 'overrun')}: '
                    '${Money.inline(f.overrun!, lang: lang)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Filtered 6-month expense/income trend (twin bars per month).
class _BiTrend extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _BiTrend({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxV = 0;
    for (final m in s.trend) {
      if (m.expense > maxV) maxV = m.expense;
      if (m.income > maxV) maxV = m.income;
    }
    if (maxV <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'trend')),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in s.trend)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 10,
                              height: 12 + 64 * m.expense / maxV,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 10,
                              height: 12 + 64 * m.income / maxV,
                              decoration: BoxDecoration(
                                color: AppColors.income,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${m.month}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Drill-down category tree: rolled-up parents expand to children;
/// tapping any node opens its transaction detail. Type-aware (income
/// filter drills the income tree).
class _DrillTree extends ConsumerStatefulWidget {
  final String lang;
  final BiSnapshot s;
  const _DrillTree({required this.lang, required this.s});

  @override
  ConsumerState<_DrillTree> createState() => _DrillTreeState();
}

class _DrillTreeState extends ConsumerState<_DrillTree> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final s = widget.s;
    final type = context
        .dependOnInheritedWidgetOfExactType<_BiTypeScope>()
        ?.type;
    final raw = type == 'income' ? s.incomeByCat : s.byCategory;
    final byId = {for (final c in s.cats) c.id: c};
    final rolled = CategoryHierarchy.rollUp(raw, s.cats);
    final parents =
        rolled.entries
            .where((e) => e.value > 0)
            .where((e) => e.key == null || byId[e.key]?.parentId == null)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (parents.isEmpty) return const SizedBox.shrink();
    final total = type == 'income' ? s.income : s.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'byCategory')),
        Text(
          Strings.get(lang, 'drillDown'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        for (final e in parents) ...[
          _drillRow(context, lang, s, byId, total, e.key, e.value,
              isParent: true),
          if (_expanded == e.key)
            for (final c in s.cats)
              if (c.parentId == e.key && (rolled[c.id] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 20),
                  child: _drillRow(
                    context,
                    lang,
                    s,
                    byId,
                    total,
                    c.id,
                    rolled[c.id]!,
                    isParent: false,
                  ),
                ),
        ],
      ],
    );
  }

  Widget _drillRow(
    BuildContext context,
    String lang,
    BiSnapshot s,
    Map<String, Category> byId,
    int total,
    String? id,
    int value, {
    required bool isParent,
  }) {
    final name = _catName(lang, s.cats, id);
    final share = AnalyticsStats.sharePct(part: value, total: total);
    final hasKids = isParent && id != null && s.cats.any((c) => c.parentId == id);
    return InkWell(
      onTap: () {
        if (hasKids) {
          setState(() => _expanded = _expanded == id ? null : id);
        } else if (id != null) {
          context.push('/dashboard/category/$id');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            CategoryAvatar(
              iconKey: _catIcon(s.cats, id),
              radius: 16,
              semanticLabel: name,
            ),
            const SizedBox(width: AppSpacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (share != null)
                    Text(
                      '$share${Strings.get(lang, 'pctOfExpenses')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            MoneyText(
              millimes: value,
              lang: lang,
              type: 'neutral',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (hasKids)
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? (_expanded == id
                          ? Icons.expand_more
                          : Icons.chevron_left)
                    : (_expanded == id
                          ? Icons.expand_more
                          : Icons.chevron_right),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Biggest category movers vs the previous equal range, most extreme
/// first. Same check/warn icon language as health facts; hidden when
/// no category moved on a positive baseline.
class _Movers extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _Movers({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in s.cats) c.id: c};
    final names = {
      for (final id in {...s.byCategory.keys, ...s.prevByCat.keys})
        id: id == null
            ? Strings.get(lang, 'uncategorized')
            : byId[id] == null
            ? '—'
            : CategoryHierarchy.displayName(lang, byId[id]!, byId),
    };
    final movers = Insights.buildMovers(
      current: s.byCategory,
      previous: s.prevByCat,
      names: names,
      lang: lang,
    );
    if (movers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in movers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    m.warn ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: m.warn
                        ? Theme.of(context).colorScheme.error
                        : AppColors.income,
                    semanticLabel: m.text,
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(child: Text(m.text)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Wallet + priority breakdown from one snapshot. Wallets keep their
/// own icons (never category glyphs); priority inherits the category
/// classification. Shares are whole-percent, int-only.
class _WalletSection extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _WalletSection({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (final w in s.wallets)
        if ((s.byWallet[w.id] ?? 0) > 0) w,
    ];
    final prioTotal = s.byPriority.values.fold(0, (a, b) => a + b);
    if (rows.isEmpty && prioTotal <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'byWallet')),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 68),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                WalletAvatar(
                  iconKey: rows[i].icon,
                  radius: 16,
                  semanticLabel: rows[i].name,
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Text(
                    rows[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                MoneyText(
                  millimes: s.byWallet[rows[i].id] ?? 0,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        if (prioTotal > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final p in const ['important', 'normal', 'fun'])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, p),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      MoneyText(
                        millimes: s.byPriority[p] ?? 0,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Inherited type scope so the drill tree follows the type chips
/// without threading parameters through every row.
class _BiTypeScope extends InheritedWidget {
  final String? type;
  const _BiTypeScope({required this.type, required super.child});
  @override
  bool updateShouldNotify(_BiTypeScope old) => old.type != type;
}

/// Budget vs actual anchored to the snapshot month: overall plus every
/// per-category row, all through the shared BudgetBar.
class _BudgetVsActual extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _BudgetVsActual({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    if (s.overallBudget == null && s.budgetRows.isEmpty) {
      return const SizedBox.shrink();
    }
    final byId = {for (final c in s.cats) c.id: c};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'budgetVsActual')),
        if (s.overallBudget != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.get(lang, 'budget'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                BudgetBar(
                  spentMillimes: s.overallSpent,
                  totalMillimes: s.overallBudget!,
                  lang: lang,
                ),
              ],
            ),
          ),
        if (s.overallBudget != null && s.budgetRows.isNotEmpty)
          const SizedBox(height: AppSpacing.sm),
        for (final r in s.budgetRows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  byId[r.categoryId] == null
                      ? '—'
                      : CategoryHierarchy.displayName(
                          lang,
                          byId[r.categoryId]!,
                          byId,
                        ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                BudgetBar(
                  spentMillimes: r.spent,
                  totalMillimes: r.budget,
                  lang: lang,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

/// Transparent health score: hero number plus every input with its
/// points and weight, missing inputs flagged, debt facts alongside.
class _HealthSection extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _HealthSection({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final util = Kpi.budgetUtilization(
      spentMillimes: s.overallSpent,
      budgetMillimes: s.overallBudget,
    );
    final h = Kpi.healthScore(
      savingsRatePct: s.savingsRate,
      budgetUtilizationPct: util,
      expenseGrowthPct: s.growth?.pct,
      obligationsSharePct: s.obligationsShare,
    );
    String inputLabel(String key) => switch (key) {
      'savings' => Strings.get(lang, 'savingsRate'),
      'adherence' => Strings.get(lang, 'budgetAdherence'),
      'growth' => Strings.get(lang, 'expenseGrowth'),
      _ => Strings.get(lang, 'recurringShare'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'healthScore')),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${h.score}',
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      Strings.get(
                        lang,
                        h.band == 'strong'
                            ? 'healthStrong'
                            : h.band == 'steady'
                            ? 'healthSteady'
                            : 'healthStrained',
                      ),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final i in h.inputs) ...[
                Row(
                  children: [
                    Expanded(child: Text(inputLabel(i.key))),
                    Text(
                      '${i.points}/100 · ${i.weight}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (h.missing.contains(i.key))
                  Text(
                    Strings.get(lang, 'insufficientData'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
              if (s.openOwed > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(Strings.get(lang, 'openDebts')),
                    ),
                    MoneyText(
                      millimes: s.openOwed,
                      lang: lang,
                      type: 'neutral',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
              if (s.overdueDebts > 0)
                Text(
                  '${Strings.get(lang, 'overdue')}: ${s.overdueDebts}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
