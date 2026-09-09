import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/insights.dart';
import 'package:masroufi/core/analytics/periods.dart';
import 'package:masroufi/core/analytics/stats.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

void main() {
  group('Periods', () {
    test('day bounds are half-open single days', () {
      final now = DateTime(2026, 9, 7, 15, 30);
      final d = Periods.day(now);
      expect(d.start, DateTime(2026, 9, 7));
      expect(d.end, DateTime(2026, 9, 8));
      final y = Periods.yesterday(now);
      expect(y.start, DateTime(2026, 9, 6));
      expect(y.end, DateTime(2026, 9, 7));
    });

    test('week respects monday/sunday/saturday starts', () {
      final wed = DateTime(2026, 9, 9, 12); // a Wednesday
      final mon = Periods.week(wed);
      expect(mon.start.weekday, DateTime.monday);
      expect(mon.end.difference(mon.start), const Duration(days: 7));
      final sun = Periods.week(wed, 'sunday');
      expect(sun.start.weekday, DateTime.sunday);
      expect(sun.end.difference(sun.start), const Duration(days: 7));
      final sat = Periods.week(wed, 'saturday');
      expect(sat.start.weekday, DateTime.saturday);
      expect(sat.end.difference(sat.start), const Duration(days: 7));
      // Unknown values fall back to Monday.
      final fallback = Periods.week(wed, 'friday');
      expect(fallback.start.weekday, DateTime.monday);
    });

    test('month/lastMonth/year bounds', () {
      final now = DateTime(2026, 9, 15);
      final m = Periods.month(now);
      expect(m.start, DateTime(2026, 9, 1));
      expect(m.end, DateTime(2026, 10, 1));
      final lm = Periods.lastMonth(now);
      expect(lm.start, DateTime(2026, 8, 1));
      expect(lm.end, DateTime(2026, 9, 1));
      final jan = Periods.lastMonth(DateTime(2026, 1, 10));
      expect(jan.start, DateTime(2025, 12, 1));
      expect(jan.end, DateTime(2026, 1, 1));
      final y = Periods.year(now);
      expect(y.start, DateTime(2026, 1, 1));
      expect(y.end, DateTime(2027, 1, 1));
    });

    test('lastCompletedMonths excludes current, oldest first', () {
      final months = Periods.lastCompletedMonths(DateTime(2026, 9, 15), 2);
      expect(months, [(year: 2026, month: 7), (year: 2026, month: 8)]);
      final wrapped = Periods.lastCompletedMonths(DateTime(2026, 1, 10), 2);
      expect(wrapped, [(year: 2025, month: 11), (year: 2025, month: 12)]);
    });

    test('last3Months spans 3 calendar months incl. year wrap', () {
      final r = Periods.last3Months(DateTime(2026, 9, 15));
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.end, DateTime(2026, 10, 1));
      final jan = Periods.last3Months(DateTime(2026, 1, 10));
      expect(jan.start, DateTime(2025, 11, 1));
      expect(jan.end, DateTime(2026, 2, 1));
    });

    test('daysInMonth handles leap years', () {
      expect(Periods.daysInMonth(2026, 2), 28);
      expect(Periods.daysInMonth(2024, 2), 29);
      expect(Periods.daysInMonth(2026, 9), 30);
    });
  });

  group('AnalyticsStats', () {
    test('averageMonthly mean, empty is zero', () {
      expect(AnalyticsStats.averageMonthly([100, 200, 300]), 200);
      expect(AnalyticsStats.averageMonthly([]), 0);
      expect(AnalyticsStats.averageMonthly([1, 2]), 2);
    });

    test('monthOverMonth null on zero or negative previous', () {
      expect(AnalyticsStats.monthOverMonth(current: 120, previous: 100), (
        diff: 20,
        pct: 20,
      ));
      expect(AnalyticsStats.monthOverMonth(current: 80, previous: 100), (
        diff: -20,
        pct: -20,
      ));
      expect(AnalyticsStats.monthOverMonth(current: 50, previous: 0), isNull);
      expect(AnalyticsStats.monthOverMonth(current: 50, previous: -10), isNull);
    });

    test('partialMonth null when nothing elapsed or spent', () {
      expect(
        AnalyticsStats.partialMonth(
          spentSoFar: 300,
          elapsedDays: 10,
          daysInMonth: 30,
        ),
        (daily: 30, projected: 900),
      );
      expect(
        AnalyticsStats.partialMonth(
          spentSoFar: 300,
          elapsedDays: 0,
          daysInMonth: 30,
        ),
        isNull,
      );
      expect(
        AnalyticsStats.partialMonth(
          spentSoFar: 0,
          elapsedDays: 10,
          daysInMonth: 30,
        ),
        isNull,
      );
    });

    test('sharePct null on zero total', () {
      expect(AnalyticsStats.sharePct(part: 25, total: 100), 25);
      expect(AnalyticsStats.sharePct(part: 10, total: 0), isNull);
      expect(AnalyticsStats.sharePct(part: -5, total: 100), isNull);
    });
  });

  group('Insights.buildInsights', () {
    test('renders all 7 templates in English', () {
      final lines = Insights.buildInsights(
        currentExpense: 80000,
        previousExpense: 100000,
        topCatName: 'Café',
        funSharePct: 15,
        incomeMoM: (diff: 50000, pct: 10),
        dailyAvgFormatted: '12.500 TND',
        lang: 'en',
      );
      expect(lines, [
        'You spent 20% less this month than last month.',
        'Café is your largest expense category this month.',
        'Fun spending is 15% of your expenses.',
        'Your income grew 10% vs last month.',
        'You spend about 12.500 TND per day.',
      ]);
    });

    test('up/down variants pick the right template', () {
      final more = Insights.buildInsights(
        currentExpense: 120000,
        previousExpense: 100000,
        topCatName: null,
        funSharePct: null,
        incomeMoM: (diff: -30000, pct: -15),
        dailyAvgFormatted: null,
        lang: 'en',
      );
      expect(more, [
        'You spent 20% more this month than last month.',
        'Your income fell 15% vs last month.',
      ]);
    });

    test('fr/ar spot-check placeholder substitution', () {
      final fr = Insights.buildInsights(
        currentExpense: 80000,
        previousExpense: 100000,
        topCatName: null,
        funSharePct: null,
        incomeMoM: null,
        dailyAvgFormatted: null,
        lang: 'fr',
      );
      expect(fr, ['Vous avez dépensé 20% de moins ce mois-ci.']);
      final ar = Insights.buildInsights(
        currentExpense: 80000,
        previousExpense: 100000,
        topCatName: 'مقهى',
        funSharePct: null,
        incomeMoM: null,
        dailyAvgFormatted: null,
        lang: 'ar',
      );
      expect(ar, [
        'أنفقت 20% أقل هذا الشهر من الشهر الماضي.',
        'مقهى هو أكبر تصنيف إنفاق هذا الشهر.',
      ]);
    });

    test('null-skipping yields empty list on insufficient data', () {
      final lines = Insights.buildInsights(
        currentExpense: 0,
        previousExpense: 0,
        topCatName: null,
        funSharePct: null,
        incomeMoM: null,
        dailyAvgFormatted: null,
        lang: 'en',
      );
      expect(lines, isEmpty);
      // Zero change and empty strings are noise: skipped too.
      final flat = Insights.buildInsights(
        currentExpense: 50000,
        previousExpense: 50000,
        topCatName: '',
        funSharePct: null,
        incomeMoM: (diff: 0, pct: 0),
        dailyAvgFormatted: '',
        lang: 'en',
      );
      expect(flat, isEmpty);
    });
  });

  group('Insights.buildMovers', () {
    test('ranks by absolute change, caps, skips noise', () {
      const names = {'food': 'Food', 'taxi': 'Taxi', 'new': 'New'};
      final movers = Insights.buildMovers(
        current: const {'food': 124000, 'taxi': 90000, 'new': 5000},
        previous: const {'food': 100000, 'taxi': 100000, 'new': 0},
        names: names,
        lang: 'en',
      );
      // food +24% warn, taxi -10% info; 'new' has no baseline: skipped.
      expect(movers, hasLength(2));
      expect(movers[0].text, 'Food +24% vs previous period');
      expect(movers[0].warn, isTrue);
      expect(movers[1].text, 'Taxi -10% vs previous period');
      expect(movers[1].warn, isFalse);
    });

    test('limit and locale templates', () {
      final many = Insights.buildMovers(
        current: const {'a': 200, 'b': 300, 'c': 10, 'd': 10},
        previous: const {'a': 100, 'b': 100, 'c': 100, 'd': 100},
        names: const {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'},
        lang: 'en',
        limit: 2,
      );
      expect(many, hasLength(2));
      final fr = Insights.buildMovers(
        current: const {'food': 124000},
        previous: const {'food': 100000},
        names: const {'food': 'Alimentation'},
        lang: 'fr',
      );
      expect(
        fr.single.text,
        'Alimentation : +24% par rapport à la période précédente',
      );
      final ar = Insights.buildMovers(
        current: const {'food': 124000},
        previous: const {'food': 100000},
        names: const {'food': 'طعام'},
        lang: 'ar',
      );
      expect(ar.single.text, contains('+24%'));
      expect(ar.single.text, contains('طعام'));
    });
  });

  group('Insights.buildHealth', () {
    test('within/over budget facts with severity', () {
      final ok = Insights.buildHealth(
        budgetMillimes: 2000000,
        monthSpentMillimes: 1260000,
        secondTopCat: null,
        daysLeft: 20,
        lang: 'en',
      );
      expect(
        ok.map((h) => (h.text, h.warn)),
        contains(('Within budget', false)),
      );
      final over = Insights.buildHealth(
        budgetMillimes: 100000,
        monthSpentMillimes: 150000,
        secondTopCat: null,
        daysLeft: 20,
        lang: 'en',
      );
      expect(
        over.map((h) => (h.text, h.warn)),
        contains(('Over budget', true)),
      );
      // No budget → no budget line, other facts survive.
      final nobudget = Insights.buildHealth(
        budgetMillimes: null,
        monthSpentMillimes: 50000,
        secondTopCat: 'Transport',
        daysLeft: 5,
        lang: 'en',
      );
      expect(nobudget, hasLength(2));
      expect(nobudget.any((h) => h.warn), isFalse);
    });

    test('second rank + days facts, localized', () {
      final fr = Insights.buildHealth(
        budgetMillimes: null,
        monthSpentMillimes: 0,
        secondTopCat: 'Transport',
        daysLeft: 18,
        lang: 'fr',
      );
      expect(fr.map((h) => h.text), contains('Transport deuxième ce mois-ci'));
      final ar = Insights.buildHealth(
        budgetMillimes: null,
        monthSpentMillimes: 0,
        secondTopCat: null,
        daysLeft: 18,
        lang: 'ar',
      );
      expect(ar.single.text, 'متبقي 18 يوم');
    });
  });

  group('AnalyticsRepo in-memory', () {
    late AppDb db;
    late WalletsRepo wallets;
    late TransactionsRepo txns;
    late CategoriesRepo cats;
    late AnalyticsRepo analytics;
    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      wallets = WalletsRepo(db);
      txns = TransactionsRepo(db);
      cats = CategoriesRepo(db);
      analytics = AnalyticsRepo(db);
    });
    tearDown(() => db.close());

    test('sums exclude transfers', () async {
      final cash = await wallets.create(name: 'Cash');
      final bank = await wallets.create(name: 'Bank');
      final start = DateTime(2026, 9, 1);
      final end = DateTime(2026, 10, 1);
      await txns.addExpense(
        amountMillimes: 10000,
        walletId: cash,
        when: DateTime(2026, 9, 5),
      );
      await txns.addIncome(
        amountMillimes: 50000,
        walletId: cash,
        when: DateTime(2026, 9, 6),
      );
      await txns.addTransfer(
        amountMillimes: 20000,
        fromWalletId: cash,
        toWalletId: bank,
        when: DateTime(2026, 9, 7),
      );
      expect(await analytics.expenseTotal(start, end), 10000);
      expect(await analytics.incomeTotal(start, end), 50000);
    });

    test('by-category groups null separately', () async {
      final cash = await wallets.create(name: 'Cash');
      final food = await cats.create('Food');
      await txns.addExpense(
        amountMillimes: 7000,
        walletId: cash,
        categoryId: food,
        when: DateTime(2026, 9, 5),
      );
      await txns.addExpense(
        amountMillimes: 3000,
        walletId: cash,
        when: DateTime(2026, 9, 6),
      );
      final byCat = await analytics.expenseByCategory(
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      expect(byCat[food], 7000);
      expect(byCat[null], 3000);
    });

    test('by-priority puts uncategorized in normal', () async {
      final cash = await wallets.create(name: 'Cash');
      final gym = await cats.create('Gym', priority: 'important');
      await txns.addExpense(
        amountMillimes: 9000,
        walletId: cash,
        categoryId: gym,
        when: DateTime(2026, 9, 5),
      );
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        when: DateTime(2026, 9, 6),
      );
      final byPri = await analytics.expenseByPriority(
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      expect(byPri['important'], 9000);
      expect(byPri['normal'], 1000);
    });

    test('monthlySeries with and without current month', () async {
      final cash = await wallets.create(name: 'Cash');
      final now = DateTime(2026, 9, 15);
      await txns.addExpense(
        amountMillimes: 8000,
        walletId: cash,
        when: DateTime(2026, 7, 10),
      );
      await txns.addIncome(
        amountMillimes: 40000,
        walletId: cash,
        when: DateTime(2026, 8, 10),
      );
      await txns.addExpense(
        amountMillimes: 2000,
        walletId: cash,
        when: DateTime(2026, 9, 2),
      );
      final completed = await analytics.monthlySeries(
        now: now,
        monthsBack: 2,
        includeCurrent: false,
      );
      expect(completed.map((s) => (s.year, s.month)), [(2026, 7), (2026, 8)]);
      expect(completed[0].expense, 8000);
      expect(completed[1].income, 40000);
      final withCurrent = await analytics.monthlySeries(
        now: now,
        monthsBack: 1,
      );
      expect(withCurrent.last.month, 9);
      expect(withCurrent.last.expense, 2000);
    });

    test('dailyExpenseTotals maps each day', () async {
      final cash = await wallets.create(name: 'Cash');
      await txns.addExpense(
        amountMillimes: 5000,
        walletId: cash,
        when: DateTime(2026, 9, 1, 10),
      );
      await txns.addExpense(
        amountMillimes: 1500,
        walletId: cash,
        when: DateTime(2026, 9, 3, 20),
      );
      final days = await analytics.dailyExpenseTotals(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 4),
      );
      expect(days[DateTime(2026, 9, 1)], 5000);
      expect(days[DateTime(2026, 9, 2)], 0);
      expect(days[DateTime(2026, 9, 3)], 1500);
    });
  });
}
