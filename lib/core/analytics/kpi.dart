import 'stats.dart';

/// Personal-finance KPIs (BI engine). Pure, int-millimes in, documented
/// numbers out. Percentages are whole percents, half-up, null when the
/// denominator is missing (never divide by zero, never show noise).
///
/// Health-score weights (frozen contract, shown with every score):
/// savings rate 35, budget adherence 30, expense growth 20, fixed
/// obligations 15. Each input contributes 0-100; the score is their
/// weighted mean, rounded half-up.
abstract final class Kpi {
  /// Net cash flow: income minus expense (may be negative).
  static int netCashFlow({
    required int incomeMillimes,
    required int expenseMillimes,
  }) => incomeMillimes - expenseMillimes;

  /// Savings rate in whole percent, or null when income is 0.
  /// Negative when spending exceeds income (overspend is signal).
  static int? savingsRate({
    required int incomeMillimes,
    required int expenseMillimes,
  }) {
    if (incomeMillimes <= 0) return null;
    final diff = incomeMillimes - expenseMillimes;
    var pct = ((diff * 100).abs() + incomeMillimes ~/ 2) ~/ incomeMillimes;
    if (diff < 0) pct = -pct;
    return pct;
  }

  /// Expense growth vs a previous period, or null when previous is 0.
  static ({int diff, int pct})? expenseGrowth({
    required int current,
    required int previous,
  }) => AnalyticsStats.monthOverMonth(current: current, previous: previous);

  /// Budget utilization in whole percent, or null without a budget.
  /// Above 100 means over budget (factual, not capped).
  static int? budgetUtilization({
    required int spentMillimes,
    required int? budgetMillimes,
  }) {
    if (budgetMillimes == null || budgetMillimes <= 0) return null;
    return ((spentMillimes * 100 + budgetMillimes ~/ 2) ~/ budgetMillimes);
  }

  /// Transparent financial-health composite. Every input is returned
  /// alongside the score so the UI can show the full breakdown and the
  /// number is never mysterious. Missing inputs score 50 (neutral) and
  /// are flagged via [missing].
  static ({
    int score,
    String band,
    List<({String key, int points, int weight})> inputs,
    List<String> missing,
  })
  healthScore({
    int? savingsRatePct,
    int? budgetUtilizationPct,
    int? expenseGrowthPct,
    int? obligationsSharePct,
  }) {
    int clamp(int v) => v.clamp(0, 100);
    final missing = <String>[];
    // Savings: 50% rate maps to 100 points, 0% to 50, deeply negative
    // floors at 0. Linear, documented, no magic curves.
    int savingsPoints;
    if (savingsRatePct == null) {
      savingsPoints = 50;
      missing.add('savings');
    } else {
      savingsPoints = clamp(50 + savingsRatePct);
    }
    // Adherence: 100% utilization (exactly on budget) is perfect;
    // each point away costs 2, floored at 0.
    int adherencePoints;
    if (budgetUtilizationPct == null) {
      adherencePoints = 50;
      missing.add('budget');
    } else {
      adherencePoints = clamp(100 - (budgetUtilizationPct - 100).abs() * 2);
    }
    // Growth: flat (0%) is 80; each growth point costs 2, each shrink
    // point earns 1 up to 100.
    int growthPoints;
    if (expenseGrowthPct == null) {
      growthPoints = 50;
      missing.add('growth');
    } else if (expenseGrowthPct >= 0) {
      growthPoints = clamp(80 - expenseGrowthPct * 2);
    } else {
      growthPoints = clamp(80 - expenseGrowthPct);
    }
    // Obligations (recurring + debt share of income): under 20% is
    // full marks, each point above costs 3.
    int obligationsPoints;
    if (obligationsSharePct == null) {
      obligationsPoints = 50;
      missing.add('obligations');
    } else {
      final over = obligationsSharePct - 20;
      obligationsPoints = over <= 0 ? 100 : clamp(100 - over * 3);
    }
    const weights = {
      'savings': 35,
      'adherence': 30,
      'growth': 20,
      'obligations': 15,
    };
    final score =
        ((savingsPoints * weights['savings']! +
                    adherencePoints * weights['adherence']! +
                    growthPoints * weights['growth']! +
                    obligationsPoints * weights['obligations']! +
                    50) ~/
                100);
    final band = score >= 75
        ? 'strong'
        : score >= 50
        ? 'steady'
        : 'strained';
    return (
      score: score,
      band: band,
      inputs: [
        (key: 'savings', points: savingsPoints, weight: weights['savings']!),
        (
          key: 'adherence',
          points: adherencePoints,
          weight: weights['adherence']!,
        ),
        (key: 'growth', points: growthPoints, weight: weights['growth']!),
        (
          key: 'obligations',
          points: obligationsPoints,
          weight: weights['obligations']!,
        ),
      ],
      missing: missing,
    );
  }
}
