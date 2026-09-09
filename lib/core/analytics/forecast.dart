import 'periods.dart';
import 'stats.dart';

/// Spending forecast (BI engine). Pure run-rate projection reusing
/// [AnalyticsStats.partialMonth]: current spend over elapsed days scales
/// to the full month. Returns null when there is nothing to project
/// from (no spend yet or no days elapsed).
abstract final class Forecast {
  static ({int projected, int? overrun, int pacePct})? project({
    required int spentSoFarMillimes,
    required DateTime now,
    required int? budgetMillimes,
  }) {
    final daysInMonth = Periods.daysInMonth(now.year, now.month);
    final elapsed = now.day.clamp(1, daysInMonth);
    final partial = AnalyticsStats.partialMonth(
      spentSoFar: spentSoFarMillimes,
      elapsedDays: elapsed,
      daysInMonth: daysInMonth,
    );
    if (partial == null) return null;
    final pacePct = budgetMillimes == null || budgetMillimes <= 0
        ? 100
        : ((partial.projected * 100 + budgetMillimes ~/ 2) ~/ budgetMillimes);
    return (
      projected: partial.projected,
      overrun: budgetMillimes == null
          ? null
          : partial.projected - budgetMillimes,
      pacePct: pacePct,
    );
  }
}
