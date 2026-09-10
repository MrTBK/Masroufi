/// What-if simulator (P1 BI upgrade).
///
/// Pure int-millimes scenarios: "what if I cut category X by p%?".
/// Never touches the ledger; returns saved-per-month + new projected
/// total so the UI slider stays honest. Percentages are whole ints.
abstract final class WhatIf {
  /// Savings from cutting [categorySpendMillimes] by [cutPct] (0-100).
  /// Returns monthly saved millimes, half-up on the cut.
  static int savedByCut({
    required int categorySpendMillimes,
    required int cutPct,
  }) {
    if (categorySpendMillimes <= 0) return 0;
    final p = cutPct.clamp(0, 100);
    if (p == 0) return 0;
    return ((categorySpendMillimes * p + 50) ~/ 100);
  }

  /// Apply several cuts at once: [cuts] maps category id → cut pct.
  /// [spendByCat] maps category id → current spend. Returns total saved
  /// plus per-category saved lines, biggest first.
  static ({int totalSaved, List<({String? id, int saved})> lines}) apply({
    required Map<String?, int> spendByCat,
    required Map<String?, int> cuts,
  }) {
    final lines = <({String? id, int saved})>[];
    var total = 0;
    cuts.forEach((id, pct) {
      final spend = spendByCat[id] ?? 0;
      final saved = savedByCut(categorySpendMillimes: spend, cutPct: pct);
      if (saved > 0) {
        lines.add((id: id, saved: saved));
        total += saved;
      }
    });
    lines.sort((a, b) => b.saved.compareTo(a.saved));
    return (totalSaved: total, lines: lines);
  }

  /// New projected month total after saving [savedMillimes] off
  /// [projectedMillimes]. Floors at 0, never negative.
  static int projectedAfter({
    required int projectedMillimes,
    required int savedMillimes,
  }) {
    final v = projectedMillimes - savedMillimes;
    return v < 0 ? 0 : v;
  }
}
