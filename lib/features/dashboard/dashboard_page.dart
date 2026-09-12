import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hide intl's own TextDirection class (shadows Flutter's enum).
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/ads/ad_banner.dart';
import '../../core/ai/ai_sheet.dart';
import '../../core/analytics/bi_scope.dart';
import '../../core/analytics/forecast_v2.dart';
import '../../core/export/bi_export.dart';
import '../../core/export/monthly_statement.dart';
import '../../core/analytics/insights.dart';
import '../../core/analytics/kpi.dart';
import '../../core/analytics/periods.dart';
import '../../core/analytics/stats.dart';
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

part 'widgets/bi_widgets.dart';
part 'widgets/section_widgets.dart';

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
  final total = await walletsRepo.visibleBalance();
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
      bottomNavigationBar: const AdBanner(slot: 'dashboard'),
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
          lang: lang,
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
                  lang: lang,
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
                      _ExportRow(lang: lang, s: s),
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
