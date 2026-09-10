import 'stats.dart';

/// Seasonal analytics over int millimes (P1 BI upgrade).
///
/// Pure helpers for year-over-year on ANY range (not just exact calendar
/// months) plus seasonal averages. All math stays integer-only; null means
/// "insufficient data", never zero-noise.
abstract final class Seasonality {
  /// Shift a half-open [start, end) range back by [years] (default 1).
  /// Used to build YoY comparison ranges for arbitrary scopes.
  static ({DateTime start, DateTime end}) shiftYearsBack(
    DateTime start,
    DateTime end, {
    int years = 1,
  }) {
    return (
      start: DateTime(start.year - years, start.month, start.day),
      end: DateTime(end.year - years, end.month, end.day),
    );
  }

  /// YoY comparison for any range, given current + prior-year totals.
  /// Delegates to [AnalyticsStats.monthOverMonth] (null when prior <= 0).
  static ({int diff, int pct})? yoyForRange({
    required int current,
    required int priorYear,
  }) => AnalyticsStats.monthOverMonth(current: current, previous: priorYear);

  /// Seasonal average: int-mean of completed-month expenses, rounded
  /// half-up. Empty list yields null (no signal), never 0-noise.
  static int? seasonalAverage(List<int> completedMonthExpenses) {
    final nonZero = completedMonthExpenses.where((v) => v > 0).toList();
    if (nonZero.isEmpty) return null;
    return AnalyticsStats.averageMonthly(nonZero);
  }

  /// Last [n] completed-month expense totals → average + min + max.
  /// Returns null when fewer than 2 completed months have spend
  /// (need a baseline before showing a band).
  static ({int avg, int min, int max})? band(List<int> completed) {
    final spend = completed.where((v) => v > 0).toList();
    if (spend.length < 2) return null;
    final avg = AnalyticsStats.averageMonthly(spend);
    var min = spend.first;
    var max = spend.first;
    for (final v in spend) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return (avg: avg, min: min, max: max);
  }
}
