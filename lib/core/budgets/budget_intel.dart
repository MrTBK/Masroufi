import '../analytics/periods.dart';
import '../analytics/stats.dart';

/// Budget intelligence (Track 6, no schema, display-level only).
///
/// - Projection: reuses [AnalyticsStats.partialMonth] run-rate; alerts when
///   the projected month-end spend exceeds the budget.
/// - Rollover: global opt-in toggle; when enabled, unused previous-month
///   budget (max(0, prevBudget - prevSpent)) adds to the current budget for
///   DISPLAY only. Ledger untouched.
/// - Copy-last-month: idempotent batch upsert lives in the repos (only
///   inserts missing target cells, never overwrites).
abstract final class BudgetIntel {
  /// Pure projection check. Returns the projected total when an alert
  /// should fire (projected > budget), else null. Month-boundary safe:
  /// uses [Periods.daysInMonth] for the month length.
  static int? projectionAlert({
    required int spentSoFar,
    required DateTime now,
    required int budgetMillimes,
  }) {
    if (budgetMillimes <= 0) return null;
    final daysInMonth = Periods.daysInMonth(now.year, now.month);
    final elapsed = now.day.clamp(1, daysInMonth);
    final partial = AnalyticsStats.partialMonth(
      spentSoFar: spentSoFar,
      elapsedDays: elapsed,
      daysInMonth: daysInMonth,
    );
    if (partial == null) return null;
    return partial.projected > budgetMillimes ? partial.projected : null;
  }

  /// Display-level rollover: effective budget = current + leftover.
  /// Leftover is clamped at >= 0 (over-spend never reduces next month).
  static int effectiveBudget({
    required int currentBudgetMillimes,
    required int? prevBudgetMillimes,
    required int? prevSpentMillimes,
    required bool rolloverEnabled,
  }) {
    if (!rolloverEnabled) return currentBudgetMillimes;
    if (prevBudgetMillimes == null || prevSpentMillimes == null) {
      return currentBudgetMillimes;
    }
    final leftover = prevBudgetMillimes - prevSpentMillimes;
    return currentBudgetMillimes + (leftover > 0 ? leftover : 0);
  }

  /// Previous calendar month of [now] (year, month), month-boundary safe
  /// (Jan → Dec of prior year).
  static ({int year, int month}) prevMonth(DateTime now) =>
      now.month == 1
      ? (year: now.year - 1, month: 12)
      : (year: now.year, month: now.month - 1);
}
