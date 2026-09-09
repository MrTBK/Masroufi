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
      if (s.monthBudget != null) ['month_budget_millimes', s.monthBudget!],
      ['month_spent_millimes', s.monthSpent],
      if (s.overallBudget != null) [
        'overall_budget_millimes',
        s.overallBudget!,
      ],
      ['overall_spent_millimes', s.overallSpent],
      ['monthly_obligations_millimes', s.monthlyObligations],
      if (s.obligationsShare != null)
        ['obligations_share_pct', s.obligationsShare!],
      ['open_owed_millimes', s.openOwed],
      ['overdue_debts', s.overdueDebts],
    ];
    return const ListToCsvConverter().convert(rows);
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
