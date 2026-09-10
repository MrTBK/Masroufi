import 'periods.dart';
import 'stats.dart';

/// Recurring-aware spending forecast (P1 BI upgrade).
///
/// V1 ([Forecast]) is pure run-rate: spent-so-far / elapsed * daysInMonth.
/// V2 adds:
/// - remaining recurring obligations for the rest of the month
///   ([remainingRecurringMillimes], precomputed via
///   `FilteredAnalytics.monthlyRuleEstimate` prorated by the caller), and
/// - a 3-month moving-average anchor ([avg3mMillimes]) to form a
///   low/high confidence band.
///
/// All int millimes, no floats. Null when there is nothing to project.
abstract final class ForecastV2 {
  static ({int projected, int low, int high, int? overrun, int pacePct})?
  project({
    required int spentSoFarMillimes,
    required DateTime now,
    required int? budgetMillimes,
    int remainingRecurringMillimes = 0,
    int? avg3mMillimes,
  }) {
    final daysInMonth = Periods.daysInMonth(now.year, now.month);
    final elapsed = now.day.clamp(1, daysInMonth);
    final partial = AnalyticsStats.partialMonth(
      spentSoFar: spentSoFarMillimes,
      elapsedDays: elapsed,
      daysInMonth: daysInMonth,
    );
    if (partial == null && remainingRecurringMillimes <= 0) return null;

    final runRate = partial?.projected ?? spentSoFarMillimes;
    final recurring = remainingRecurringMillimes < 0
        ? 0
        : remainingRecurringMillimes;
    final projected = runRate + recurring;

    // Confidence band: blend run-rate+recurring with 3m average when
    // available (±15% half-up). Without an anchor, band collapses.
    int low = projected;
    int high = projected;
    if (avg3mMillimes != null && avg3mMillimes > 0) {
      final blended = (projected + avg3mMillimes) ~/ 2;
      final margin = (blended * 15 + 50) ~/ 100;
      low = blended - margin;
      if (low < 0) low = 0;
      high = blended + margin;
    }

    final pacePct = budgetMillimes == null || budgetMillimes <= 0
        ? 100
        : ((projected * 100 + budgetMillimes ~/ 2) ~/ budgetMillimes);
    return (
      projected: projected,
      low: low,
      high: high,
      overrun: budgetMillimes == null ? null : projected - budgetMillimes,
      pacePct: pacePct,
    );
  }

  /// Prorate a monthly recurring estimate to the days remaining in the
  /// month (including today). Int-only, half-up.
  static int prorateRemaining({
    required int monthlyEstimateMillimes,
    required DateTime now,
  }) {
    if (monthlyEstimateMillimes <= 0) return 0;
    final daysInMonth = Periods.daysInMonth(now.year, now.month);
    final remaining = (daysInMonth - now.day + 1).clamp(1, daysInMonth);
    return ((monthlyEstimateMillimes * remaining + daysInMonth ~/ 2) ~/
        daysInMonth);
  }
}
