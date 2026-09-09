import '../l10n/strings.dart';
import 'stats.dart';

/// Pure insight-text engine (no I/O, no widgets).
///
/// Builds localized one-line insights from precomputed aggregates using
/// [AnalyticsStats] for month-over-month math and the `ins*` templates in
/// [Strings] (present in en/fr/ar). Every input is null-safe: insufficient
/// data simply yields no line instead of noise.
abstract final class Insights {
  static List<String> buildInsights({
    required int currentExpense,
    required int previousExpense,
    required String? topCatName,
    required int? funSharePct,
    required ({int diff, int pct})? incomeMoM,
    required String? dailyAvgFormatted,
    required String lang,
  }) {
    final out = <String>[];

    final mom = AnalyticsStats.monthOverMonth(
      current: currentExpense,
      previous: previousExpense,
    );
    if (mom != null && mom.pct != 0) {
      out.add(
        Strings.tpl(lang, mom.pct < 0 ? 'insMomLess' : 'insMomMore', {
          'p': mom.pct.abs().toString(),
        }),
      );
    }

    if (topCatName != null && topCatName.isNotEmpty) {
      out.add(Strings.tpl(lang, 'insTopCat', {'cat': topCatName}));
    }

    if (funSharePct != null) {
      out.add(Strings.tpl(lang, 'insFunShare', {'p': funSharePct.toString()}));
    }

    if (incomeMoM != null && incomeMoM.pct != 0) {
      out.add(
        Strings.tpl(lang, incomeMoM.pct > 0 ? 'insIncomeUp' : 'insIncomeDown', {
          'p': incomeMoM.pct.abs().toString(),
        }),
      );
    }

    if (dailyAvgFormatted != null && dailyAvgFormatted.isNotEmpty) {
      out.add(Strings.tpl(lang, 'insDailyAvg', {'v': dailyAvgFormatted}));
    }

    return out;
  }

  /// Per-category movers: largest absolute whole-percent changes between
  /// two equal ranges, most extreme first, capped at [limit]. Only
  /// categories with a positive previous total qualify (never divide by
  /// zero); zero-change rows are skipped. Names arrive resolved (the
  /// engine stays locale-free); each line carries warn when spending
  /// grew. Pure BI facts for the AI layer to explain later.
  static List<({String text, bool warn})> buildMovers({
    required Map<String?, int> current,
    required Map<String?, int> previous,
    required Map<String?, String> names,
    required String lang,
    int limit = 3,
  }) {
    final rows = <({String? id, int pct})>[];
    for (final e in current.entries) {
      final prev = previous[e.key] ?? 0;
      if (e.value <= 0 || prev <= 0) continue;
      final diff = e.value - prev;
      if (diff == 0) continue;
      var pct = ((diff * 100).abs() + prev ~/ 2) ~/ prev;
      if (diff < 0) pct = -pct;
      rows.add((id: e.key, pct: pct));
    }
    rows.sort((a, b) => b.pct.abs().compareTo(a.pct.abs()));
    return [
      for (final r in rows.take(limit))
        (
          text: Strings.tpl(lang, 'insCatGrowth', {
            'cat': names[r.id] ?? '—',
            'v': '${r.pct > 0 ? '+' : ''}${r.pct}%',
          }),
          warn: r.pct > 0,
        ),
    ];
  }

  /// Factual financial-health lines (brief §35): only data-derived facts,
  /// never an invented score. Each line carries its severity for the UI
  /// icon (check vs warning). Empty when there is nothing factual to say.
  /// - budget vs month spend → within/over (skipped when no budget).
  /// - second-top category → rank fact (skipped when absent).
  /// - days left in month → always factual when > 0.
  /// MoM direction is deliberately NOT repeated here: the insights list
  /// already renders it from the same inputs.
  static List<({String text, bool warn})> buildHealth({
    required int? budgetMillimes,
    required int monthSpentMillimes,
    required String? secondTopCat,
    required int daysLeft,
    required String lang,
  }) {
    final out = <({String text, bool warn})>[];
    if (budgetMillimes != null && budgetMillimes > 0 && monthSpentMillimes > 0) {
      out.add(
        monthSpentMillimes > budgetMillimes
            ? (text: Strings.get(lang, 'healthOver'), warn: true)
            : (text: Strings.get(lang, 'healthWithin'), warn: false),
      );
    }
    if (secondTopCat != null && secondTopCat.isNotEmpty) {
      out.add(
        (
          text: Strings.tpl(lang, 'healthSecond', {'cat': secondTopCat}),
          warn: false,
        ),
      );
    }
    if (daysLeft > 0) {
      out.add(
        (
          text: Strings.tpl(lang, 'healthDays', {'n': '$daysLeft'}),
          warn: false,
        ),
      );
    }
    return out;
  }
}
