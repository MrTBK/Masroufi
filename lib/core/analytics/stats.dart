/// Pure analytics math over int millimes (unit-testable, no I/O).
///
/// Display-only derived stats use integer rounding; raw ledger values are
/// never mutated. Averages always state their window explicitly — current
/// partial months are never silently averaged in.
abstract final class AnalyticsStats {
  /// Integer mean of monthly totals, rounded half up. Empty list → 0.
  static int averageMonthly(List<int> completedMonthTotals) {
    if (completedMonthTotals.isEmpty) return 0;
    var total = 0;
    for (final v in completedMonthTotals) {
      total += v;
    }
    final n = completedMonthTotals.length;
    return (total + n ~/ 2) ~/ n;
  }

  /// Month-over-month comparison, or null when [previous] is 0
  /// (insufficient data — never divide by zero, never show noise).
  /// pct is a signed whole percent, rounded half up on the magnitude.
  /// Pure integer math: no floats anywhere near money.
  static ({int diff, int pct})? monthOverMonth({
    required int current,
    required int previous,
  }) {
    if (previous <= 0) return null;
    final diff = current - previous;
    var pct = ((diff * 100).abs() + previous ~/ 2) ~/ previous;
    if (diff < 0) pct = -pct;
    return (diff: diff, pct: pct);
  }

  /// Average daily expense for a partial month + labeled projection.
  /// Returns null when nothing elapsed or nothing spent.
  static ({int daily, int projected})? partialMonth({
    required int spentSoFar,
    required int elapsedDays,
    required int daysInMonth,
  }) {
    if (elapsedDays <= 0 || spentSoFar <= 0 || daysInMonth <= 0) return null;
    final daily = (spentSoFar + elapsedDays ~/ 2) ~/ elapsedDays;
    return (daily: daily, projected: daily * daysInMonth);
  }

  /// Whole-percent share of [part] in [total], or null when total is 0.
  static int? sharePct({required int part, required int total}) {
    if (total <= 0 || part < 0) return null;
    return ((part * 100 + total ~/ 2) ~/ total);
  }
}
