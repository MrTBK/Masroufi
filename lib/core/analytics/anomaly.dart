/// Anomaly detection over category spend (P1 BI upgrade).
///
/// Pure, int-millimes in, factual flags out. Uses a simple z-score rule:
/// a category is anomalous when its current spend exceeds
/// `mean + 2*sd` of its completed-month history AND exceeds an absolute
/// floor ([minMillimes], default 5 TND) to avoid noise on tiny budgets.
///
/// Integer math only: mean/variance use int division with half-up
/// rounding; sd is an integer square-root (Newton). Null-safe: short
/// history (<3 months) yields no flags, never guesses.
abstract final class Anomaly {
  /// Detect anomalous categories.
  ///
  /// [currentByCat] maps category id → current-range spend; [historyByCat]
  /// maps category id → list of completed-month spends (oldest first).
  /// Returns most-extreme first, capped at [limit].
  static List<({String? id, int current, int mean, int pctOver})> detect({
    required Map<String?, int> currentByCat,
    required Map<String, List<int>> historyByCat,
    int minMillimes = 5000,
    int limit = 3,
  }) {
    final out = <({String? id, int current, int mean, int pctOver})>[];
    for (final e in currentByCat.entries) {
      final cur = e.value;
      if (cur < minMillimes) continue;
      final hist = (historyByCat[e.key] ?? const <int>[])
          .where((v) => v > 0)
          .toList();
      if (hist.length < 3) continue;
      final mean = _mean(hist);
      if (mean <= 0 || cur <= mean) continue;
      final sd = _sd(hist, mean);
      final threshold = mean + 2 * sd;
      if (cur <= threshold) continue;
      final pctOver = ((cur - mean) * 100 + mean ~/ 2) ~/ mean;
      out.add((id: e.key, current: cur, mean: mean, pctOver: pctOver));
    }
    out.sort((a, b) => b.pctOver.compareTo(a.pctOver));
    return out.take(limit).toList();
  }

  static int _mean(List<int> vs) {
    var total = 0;
    for (final v in vs) {
      total += v;
    }
    return (total + vs.length ~/ 2) ~/ vs.length;
  }

  static int _sd(List<int> vs, int mean) {
    var sumSq = 0;
    for (final v in vs) {
      final d = v - mean;
      sumSq += d * d;
    }
    final variance = sumSq ~/ vs.length;
    return _isqrt(variance);
  }

  /// Integer square root (Newton iteration), floor.
  static int _isqrt(int n) {
    if (n <= 0) return 0;
    var x = n;
    var y = (x + 1) ~/ 2;
    while (y < x) {
      x = y;
      y = (x + n ~/ x) ~/ 2;
    }
    return x;
  }
}
