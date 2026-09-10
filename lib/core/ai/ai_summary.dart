import 'dart:convert';

import '../../data/database/category_hierarchy.dart';
import '../analytics/bi_scope.dart';

/// Compact redacted BI summary for the AI layer (P4).
///
/// Design contract (never change casually):
/// - Input is a [BiSnapshot] (on-device facts, int millimes).
/// - Output is ~1-2KB JSON: period, totals, top categories by NAME
///   (never raw ids when names exist), movers pct, forecast, budget.
/// - Notes, payees, wallet names are EXCLUDED unless [includeNotes] is
///   true AND the user explicitly opted in (`ai_include_notes`).
/// - Wallet ids are anonymized to w1..wn; category ids stay only when no
///   display name exists.
/// - AI only explains these numbers; it never recomputes money.
abstract final class AiSummaryBuilder {
  static Map<String, Object?> toCompactJson(
    BiSnapshot s, {
    required String lang,
    bool includeNotes = false,
  }) {
    final byId = {for (final c in s.cats) c.id: c};
    String catName(String? id) {
      if (id == null) return '—';
      final c = byId[id];
      if (c == null) return id;
      return CategoryHierarchy.displayName(lang, c, byId);
    }

    final topCats = s.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = [
      for (final e in topCats.take(3))
        {'cat': catName(e.key), 'millimes': e.value},
    ];

    // Anonymize wallet ids: stable w1..wn in snapshot order.
    final walletIds = s.wallets.map((w) => w.id).toList();
    final anon = {
      for (var i = 0; i < walletIds.length; i++) walletIds[i]: 'w${i + 1}',
    };
    final flows = [
      for (final e in s.byWallet.entries)
        {
          'w': anon[e.key] ?? 'w?',
          'expense': e.value,
          'net': s.netByWallet[e.key] ?? 0,
        },
    ];

    return {
      'v': 1,
      'lang': lang,
      'period': {
        'from': s.from.toIso8601String(),
        'to': s.to.toIso8601String(),
      },
      'income': s.income,
      'expense': s.expense,
      'net': s.income - s.expense,
      'txns': s.txnCount,
      if (s.savingsRate != null) 'savingsRatePct': s.savingsRate,
      if (s.growth != null)
        'mom': {'diff': s.growth!.diff, 'pct': s.growth!.pct},
      if (s.yoyAnyExpense != null) 'yoyExpense': s.yoyAnyExpense,
      if (s.avg3mExpense != null) 'avg3m': s.avg3mExpense,
      'top': top3,
      'wallets': flows,
      'forecast': {
        'projected': s.forecastProjected,
        'low': s.forecastLow,
        'high': s.forecastHigh,
        if (s.forecastOverrun != null) 'overrun': s.forecastOverrun,
        'pacePct': s.forecastPacePct,
      },
      if (s.overallBudget != null) 'budget': s.overallBudget,
      'spent': s.overallSpent,
      if (s.monthBudget != null) 'monthBudget': s.monthBudget,
      'monthSpent': s.monthSpent,
      'obligations': s.monthlyObligations,
      if (s.obligationsShare != null) 'obligSharePct': s.obligationsShare,
      // includeNotes reserves a slot for future opt-in detail; today the
      // ledger notes NEVER leave the device (no per-txn payload).
      'notesIncluded': includeNotes ? true : false,
    };
  }

  static String encode(
    BiSnapshot s, {
    required String lang,
    bool includeNotes = false,
  }) => jsonEncode(toCompactJson(s, lang: lang, includeNotes: includeNotes));
}
