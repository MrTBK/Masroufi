import 'package:csv/csv.dart';

import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../analytics/bi_scope.dart';

/// BI export builders (phase 6). Pure: rows in, CSV text out. Numbers
/// stay raw millimes/ints (machine-readable for spreadsheets); the
/// monthly PDF path reuses [MonthlyStatementBuilder] and is wired in
/// the dashboard (month containing the scope end, filtered numbers).
abstract final class BiExport {
  /// KPI summary for the scope: one metric per row.
  static String kpiCsv(BiSnapshot s) {
    const header = ['metric', 'value'];
    final growth = s.growth;
    final rows = <List<Object>>[
      header,
      ['income_millimes', s.income],
      ['expense_millimes', s.expense],
      ['net_millimes', s.income - s.expense],
      ['txn_count', s.txnCount],
      if (s.savingsRate != null) ['savings_rate_pct', s.savingsRate!],
      if (growth != null) ...[
        ['growth_diff_millimes', growth.diff],
        ['growth_pct', growth.pct],
      ],
      if (s.yoyExpense != null) ['yoy_expense_millimes', s.yoyExpense!],
      if (s.yoyAnyExpense != null)
        ['yoy_any_expense_millimes', s.yoyAnyExpense!],
      if (s.avg3mExpense != null) ['avg3m_expense_millimes', s.avg3mExpense!],
      // Recurring-aware forecast (P1): Excel-readable, millimes + pct.
      ['forecast_projected_millimes', s.forecastProjected],
      ['forecast_low_millimes', s.forecastLow],
      ['forecast_high_millimes', s.forecastHigh],
      if (s.forecastOverrun != null)
        ['forecast_overrun_millimes', s.forecastOverrun!],
      ['forecast_pace_pct', s.forecastPacePct],
      if (s.monthBudget != null) ['month_budget_millimes', s.monthBudget!],
      ['month_spent_millimes', s.monthSpent],
      if (s.overallBudget != null)
        ['overall_budget_millimes', s.overallBudget!],
      ['overall_spent_millimes', s.overallSpent],
      ['monthly_obligations_millimes', s.monthlyObligations],
      if (s.obligationsShare != null)
        ['obligations_share_pct', s.obligationsShare!],
      ['open_owed_millimes', s.openOwed],
      ['overdue_debts', s.overdueDebts],
    ];
    return const ListToCsvConverter().convert(rows);
  }

  /// Per-wallet net-flow table (P1): income − expense + transfers in − out.
  /// Excel opens this CSV directly; numbers stay raw millimes.
  static String walletFlowsCsv(BiSnapshot s) {
    const header = [
      'wallet_id',
      'wallet_name',
      'expense_millimes',
      'net_millimes',
    ];
    final names = {for (final w in s.wallets) w.id: w.name};
    return const ListToCsvConverter().convert([
      header,
      for (final e in s.byWallet.entries)
        [e.key, names[e.key] ?? e.key, e.value, s.netByWallet[e.key] ?? 0],
    ]);
  }

  /// Anomaly flags (P1): one row per anomalous category. Empty string
  /// (header only) when nothing anomalous — never noise.
  static String anomalyCsv(
    List<({String? id, int current, int mean, int pctOver})> flags, {
    required Map<String?, String> names,
  }) {
    const header = [
      'category_id',
      'category',
      'current_millimes',
      'mean_millimes',
      'pct_over',
    ];
    return const ListToCsvConverter().convert([
      header,
      for (final a in flags)
        [a.id ?? '', names[a.id] ?? '', a.current, a.mean, a.pctOver],
    ]);
  }

  /// Flat analytical dataset: one transaction per row with the full
  /// category path (Parent › Child), wallet names, and notes.
  static String datasetCsv({
    required List<Transaction> txns,
    required Map<String, Wallet> wallets,
    required Map<String, Category> cats,
    required String lang,
  }) {
    const header = [
      'date',
      'type',
      'amount_millimes',
      'category_path',
      'wallet',
      'to_wallet',
      'note',
    ];
    String walletName(String id) => wallets[id]?.name ?? id;
    String catPath(String? id) {
      if (id == null) return '';
      final c = cats[id];
      if (c == null) return id;
      return CategoryHierarchy.displayName(lang, c, cats);
    }

    return const ListToCsvConverter().convert([
      header,
      for (final t in txns)
        [
          t.occurredAt.toIso8601String(),
          t.type,
          t.amountMillimes,
          catPath(t.categoryId),
          walletName(t.walletId),
          t.toWalletId == null ? '' : walletName(t.toWalletId!),
          t.note,
        ],
    ]);
  }
}
