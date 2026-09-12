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

  /// Seasonal average: int-mean of completed-month expenses, rounded
  /// half-up. Empty list yields null (no signal), never 0-noise.
  static int? seasonalAverage(List<int> completedMonthExpenses) {
    final nonZero = completedMonthExpenses.where((v) => v > 0).toList();
    if (nonZero.isEmpty) return null;
    return AnalyticsStats.averageMonthly(nonZero);
  }
}
