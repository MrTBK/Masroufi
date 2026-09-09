import '../../data/repositories/analytics_repo.dart';
import '../../data/repositories/wallets_repo.dart';
import 'periods.dart';
import 'stats.dart';

/// Daily budget guidance (deterministic, documented, int-only):
/// remaining budget spread over the days left in the month INCLUDING
/// today. `daysLeft` is clamped to [1, daysInMonth] so the division is
/// total. A negative `remaining` (over budget) yields a negative
/// `suggested`: callers show the over-budget state, never a target.
({int remaining, int daysLeft, int suggested}) dailyGuidance({
  required int budgetMillimes,
  required int spentMillimes,
  required DateTime now,
}) {
  final daysInMonth = Periods.daysInMonth(now.year, now.month);
  final daysLeft = (daysInMonth - now.day + 1).clamp(1, daysInMonth);
  final remaining = budgetMillimes - spentMillimes;
  return (
    remaining: remaining,
    daysLeft: daysLeft,
    suggested: remaining ~/ daysLeft,
  );
}

/// Thin application services over the existing repositories.
///
/// UI must not embed SQL or duplicate money math: widgets call these
/// services (via Riverpod providers), which delegate to [AnalyticsRepo],
/// [WalletsRepo] and the pure helpers in [Periods]/[AnalyticsStats].
///
/// Definitions (kept explicit per spec §13):
/// - [dailyAverage] = periodExpense / elapsed whole days in the period
///   (elapsed = days from period start through today, min 1; for a past
///   period such as last month, the full period length).
/// - [monthlyAverage] = int-mean of the last [monthsBack] COMPLETED months
///   (current partial month excluded), via [AnalyticsStats.averageMonthly].
///   Never confuse with the current month's total.
class FinancialSummaryService {
  final AnalyticsRepo analytics;
  final WalletsRepo wallets;
  FinancialSummaryService({required this.analytics, required this.wallets});

  /// Total money for prominent summaries: non-archived, VISIBLE wallets
  /// only, so hidden balances can never leak by subtraction. Display-level
  /// exclusion; ledger math still uses `WalletsRepo.totalBalance`.
  Future<int> totalMoney() => wallets.visibleBalance();

  Future<int> spentIn(DateTime start, DateTime end) =>
      analytics.expenseTotal(start, end);

  Future<int> incomeIn(DateTime start, DateTime end) =>
      analytics.incomeTotal(start, end);

  /// Daily average for an arbitrary period. See class docs.
  Future<({int dailyAverage, int expense, int days})> averageSpending(
    DateTime start,
    DateTime end,
    DateTime now,
  ) async {
    final expense = await analytics.expenseTotal(start, end);
    final days = Periods.elapsedDays(start, end, now);
    return (dailyAverage: expense ~/ days, expense: expense, days: days);
  }

  /// Monthly average over the last [monthsBack] completed months.
  Future<({int monthlyAverage, int total, int months})> monthlyAverage(
    DateTime now, {
    int monthsBack = 3,
  }) async {
    final series = await analytics.monthlySeries(
      now: now,
      monthsBack: monthsBack,
      includeCurrent: false,
    );
    final expenses = [for (final m in series) m.expense];
    final avg = AnalyticsStats.averageMonthly(expenses);
    final total = expenses.fold(0, (a, b) => a + b);
    return (monthlyAverage: avg, total: total, months: expenses.length);
  }
}

/// Category-spending aggregation for the dashboard donut + top list.
/// Parent rollup is applied by the caller via CategoryHierarchy when a
/// primary-level view is needed; this service returns raw leaf sums.
class CategorySpendingService {
  final AnalyticsRepo analytics;
  CategorySpendingService({required this.analytics});

  Future<Map<String?, int>> expenseByCategory(DateTime start, DateTime end) =>
      analytics.expenseByCategory(start, end);

  /// Top [limit] categories sorted by spend desc, zero/negative excluded.
  Future<List<({String? id, int total})>> topCategories(
    DateTime start,
    DateTime end, {
    int limit = 5,
  }) async {
    final byCat = await analytics.expenseByCategory(start, end);
    final entries =
        byCat.entries
            .where((e) => e.value > 0)
            .map((e) => (id: e.key, total: e.value))
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return entries.take(limit).toList();
  }
}
