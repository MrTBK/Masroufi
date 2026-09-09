import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'category_hierarchy.dart';
import 'category_priority.dart';
import 'tables.dart';

part 'app_db.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    AppSettings,
    RecurringRules,
    CategoryBudgets,
    SavingsGoals,
    SavingsContributions,
    Debts,
    DebtPayments,
    TxnTemplates,
  ],
)
class AppDb extends _$AppDb {
  AppDb() : super(_open());
  AppDb.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => await m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(recurringRules);
        await m.createTable(categoryBudgets);
        await m.createTable(savingsGoals);
        await m.createTable(savingsContributions);
        await m.createTable(debts);
        await m.createTable(debtPayments);
        await m.addColumn(transactions, transactions.recurringRuleId);
      }
      if (from < 3) {
        // Privacy flag (display-only) + income/expense category kinds.
        // Defaults preserve existing behavior: balances visible,
        // every existing category stays an expense category.
        await m.addColumn(wallets, wallets.isBalanceHidden);
        await m.addColumn(categories, categories.kind);
      }
      if (from < 4) {
        // Priority classification (analytical metadata only).
        // Existing rows default to 'normal'; beforeOpen backfills
        // deterministic per-key defaults.
        await m.addColumn(categories, categories.priority);
      }
      if (from < 5) {
        // Single-level hierarchy (nullable parent ref). Existing rows
        // default to top-level (null); beforeOpen backfills parentId
        // for known default children by nameKey.
        await m.addColumn(categories, categories.parentId);
      }
      if (from < 6) {
        // Wallet card styling (display-only keys). Existing rows keep
        // teal/classic via column defaults; no data rewrite needed.
        await m.addColumn(wallets, wallets.colorKey);
        await m.addColumn(wallets, wallets.design);
      }
      if (from < 7) {
        // Transaction templates: brand-new table, empty for existing
        // users. No backfill, no data touched.
        await m.createTable(txnTemplates);
      }
    },
    beforeOpen: (details) async {
      if (details.versionBefore != null && details.versionBefore! < 4) {
        await CategoryPriority.backfill(this);
      }
      if (details.versionBefore != null && details.versionBefore! < 5) {
        await CategoryHierarchy.backfill(this);
      }
    },
  );

  static QueryExecutor _open() => driftDatabase(name: 'masroufi');

  Future<int> _scalar(String sql, List<Variable> vars) async {
    final row = await customSelect(sql, variables: vars).getSingleOrNull();
    return (row?.data.values.firstOrNull as num?)?.toInt() ?? 0;
  }

  /// Income/expense sums for a wallet, plus transfer in/out.
  Future<({int income, int expense, int tIn, int tOut})> walletFlows(
    String walletId,
  ) async {
    final income = await _scalar(
      "SELECT COALESCE(SUM(amount_millimes),0) AS s FROM transactions WHERE type='income' AND wallet_id=?",
      [Variable.withString(walletId)],
    );
    final expense = await _scalar(
      "SELECT COALESCE(SUM(amount_millimes),0) AS s FROM transactions WHERE type='expense' AND wallet_id=?",
      [Variable.withString(walletId)],
    );
    final tIn = await _scalar(
      "SELECT COALESCE(SUM(amount_millimes),0) AS s FROM transactions WHERE type='transfer' AND to_wallet_id=?",
      [Variable.withString(walletId)],
    );
    final tOut = await _scalar(
      "SELECT COALESCE(SUM(amount_millimes),0) AS s FROM transactions WHERE type='transfer' AND wallet_id=?",
      [Variable.withString(walletId)],
    );
    return (income: income, expense: expense, tIn: tIn, tOut: tOut);
  }

  static ({DateTime start, DateTime end}) monthRange(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return (start: start, end: end);
  }

  Future<({int income, int expense})> monthSums(int year, int month) async {
    final (start: start, end: end) = monthRange(year, month);
    final income = await _scalar(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      'WHERE type=? AND occurred_at>=? AND occurred_at<?',
      [
        Variable.withString('income'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    );
    final expense = await _scalar(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      'WHERE type=? AND occurred_at>=? AND occurred_at<?',
      [
        Variable.withString('expense'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    );
    return (income: income, expense: expense);
  }

  /// Expense grouped by category for a month (null category -> 'uncategorized').
  Future<Map<String?, int>> expenseByCategory(int year, int month) async {
    final (start: start, end: end) = monthRange(year, month);
    final rows = await customSelect(
      'SELECT category_id AS c, COALESCE(SUM(amount_millimes),0) AS s '
      'FROM "transactions" WHERE type=? AND occurred_at>=? AND occurred_at<? '
      'GROUP BY category_id',
      variables: [
        Variable.withString('expense'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    ).get();
    return {
      for (final r in rows)
        r.data['c'] as String?: (r.data['s'] as num?)?.toInt() ?? 0,
    };
  }
}
