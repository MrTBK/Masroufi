import 'package:drift/drift.dart';

import '../../core/analytics/periods.dart';
import '../database/app_db.dart';

/// One calendar month of ledger totals. All int millimes.
typedef MonthSlice = ({int year, int month, int income, int expense});

/// Aggregate analytics over the transaction ledger.
///
/// Every query filters on `type` explicitly, so the core money rules hold
/// everywhere by construction:
/// - transfers never match expense/income aggregates;
/// - savings contributions live in their own ledger and never appear;
/// - recurring-generated rows are ordinary expense/income rows;
/// - debt payments count exactly once through their ledger transaction.
/// Hidden balances are display-only: these sums always use raw values.
class AnalyticsRepo {
  final AppDb db;
  AnalyticsRepo(this.db);

  Future<int> _sum(String type, DateTime start, DateTime end) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND occurred_at>=? AND occurred_at<?',
          variables: [
            Variable.withString(type),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
          ],
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  /// Wallet-scoped flows over [start, end): income, expense,
  /// transfers in/out (same wallet-matching rule as `TxnFilter`: a
  /// transfer counts for both endpoints) plus the matching txn count.
  /// Powers wallet statistics; ledger math lives in `WalletsRepo`.
  Future<({int income, int expense, int tIn, int tOut, int count})>
  walletStats(String walletId, DateTime start, DateTime end) async {
    Future<int> sum(String sql, List<Variable> vars) async {
      final row = await db
          .customSelect(sql, variables: vars)
          .getSingleOrNull();
      return (row?.data.values.firstOrNull as num?)?.toInt() ?? 0;
    }

    final w = Variable.withString(walletId);
    final s = Variable.withDateTime(start);
    final e = Variable.withDateTime(end);
    const range = 'occurred_at>=? AND occurred_at<?';
    final income = await sum(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      "WHERE type='income' AND wallet_id=? AND $range",
      [w, s, e],
    );
    final expense = await sum(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      "WHERE type='expense' AND wallet_id=? AND $range",
      [w, s, e],
    );
    final tIn = await sum(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      "WHERE type='transfer' AND to_wallet_id=? AND $range",
      [w, s, e],
    );
    final tOut = await sum(
      'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
      "WHERE type='transfer' AND wallet_id=? AND $range",
      [w, s, e],
    );
    final count = await sum(
      'SELECT COUNT(*) AS s FROM "transactions" '
      "WHERE (wallet_id=? OR (type='transfer' AND to_wallet_id=?)) "
      'AND $range',
      [w, w, s, e],
    );
    return (
      income: income,
      expense: expense,
      tIn: tIn,
      tOut: tOut,
      count: count,
    );
  }

  Future<int> expenseTotal(DateTime start, DateTime end) =>
      _sum('expense', start, end);

  Future<int> incomeTotal(DateTime start, DateTime end) =>
      _sum('income', start, end);

  /// Wallet-scoped sums for the BI filter bar. Empty [walletIds] means
  /// all wallets (no extra predicate). Transfers follow the same
  /// endpoint rule as [TxnFilter]: a transfer counts when EITHER
  /// endpoint is in the set.
  Future<int> _sumW(
    String type,
    List<String> walletIds,
    DateTime start,
    DateTime end,
  ) async {
    var sql =
        'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
        'WHERE type=? AND occurred_at>=? AND occurred_at<?';
    final vars = <Variable>[
      Variable.withString(type),
      Variable.withDateTime(start),
      Variable.withDateTime(end),
    ];
    if (walletIds.isNotEmpty) {
      final list = List.filled(walletIds.length, '?').join(',');
      if (type == 'transfer') {
        sql += ' AND (wallet_id IN ($list) OR to_wallet_id IN ($list))';
        vars.addAll([
          for (final id in walletIds) Variable.withString(id),
          for (final id in walletIds) Variable.withString(id),
        ]);
      } else {
        sql += ' AND wallet_id IN ($list)';
        vars.addAll([for (final id in walletIds) Variable.withString(id)]);
      }
    }
    final row = await db.customSelect(sql, variables: vars).getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  Future<int> expenseTotalW(
    List<String> walletIds,
    DateTime start,
    DateTime end,
  ) => _sumW('expense', walletIds, start, end);

  Future<int> incomeTotalW(
    List<String> walletIds,
    DateTime start,
    DateTime end,
  ) => _sumW('income', walletIds, start, end);

  /// Transaction count honoring the BI scope. Null/empty lists match all.
  Future<int> txnCount({
    List<String>? walletIds,
    List<String>? categoryIds,
    String? type,
    DateTime? from,
    DateTime? to,
  }) async {
    final conds = <String>[];
    final vars = <Variable>[];
    if (type != null) {
      conds.add('type=?');
      vars.add(Variable.withString(type));
    }
    if (walletIds != null && walletIds.isNotEmpty) {
      final list = List.filled(walletIds.length, '?').join(',');
      conds.add('(wallet_id IN ($list) OR to_wallet_id IN ($list))');
      // Bound twice: the placeholder list appears twice (both legs).
      vars.addAll([
        for (final id in walletIds) Variable.withString(id),
        for (final id in walletIds) Variable.withString(id),
      ]);
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      final list = List.filled(categoryIds.length, '?').join(',');
      conds.add('category_id IN ($list)');
      vars.addAll([for (final id in categoryIds) Variable.withString(id)]);
    }
    if (from != null) {
      conds.add('occurred_at>=?');
      vars.add(Variable.withDateTime(from));
    }
    if (to != null) {
      conds.add('occurred_at<?');
      vars.add(Variable.withDateTime(to));
    }
    final where = conds.isEmpty ? '' : 'WHERE ${conds.join(' AND ')}';
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS s FROM "transactions" $where',
          variables: vars,
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  /// Same calendar month one year earlier (YoY anchor).
  Future<({int income, int expense})> sameMonthLastYear(
    int year,
    int month,
  ) => db.monthSums(year - 1, month);

  Future<Map<String?, int>> _byCategory(
    String type,
    DateTime start,
    DateTime end, {
    List<String>? walletIds,
  }) async {
    var sql =
        'SELECT category_id AS c, COALESCE(SUM(amount_millimes),0) AS s '
        'FROM "transactions" WHERE type=? AND occurred_at>=? AND occurred_at<? ';
    final vars = <Variable>[
      Variable.withString(type),
      Variable.withDateTime(start),
      Variable.withDateTime(end),
    ];
    if (walletIds != null && walletIds.isNotEmpty) {
      final list = List.filled(walletIds.length, '?').join(',');
      sql += 'AND wallet_id IN ($list) ';
      vars.addAll([for (final id in walletIds) Variable.withString(id)]);
    }
    final rows = await db
        .customSelect('$sql GROUP BY category_id', variables: vars)
        .get();
    return {
      for (final r in rows)
        r.data['c'] as String?: (r.data['s'] as num?)?.toInt() ?? 0,
    };
  }

  Future<Map<String?, int>> expenseByCategory(
    DateTime start,
    DateTime end, {
    List<String>? walletIds,
  }) => _byCategory('expense', start, end, walletIds: walletIds);

  Future<Map<String?, int>> incomeByCategory(
    DateTime start,
    DateTime end, {
    List<String>? walletIds,
  }) => _byCategory('income', start, end, walletIds: walletIds);

  /// Expense grouped by category priority (inherited from the category).
  /// Uncategorized rows (null category) fall in the 'normal' bucket.
  Future<Map<String, int>> expenseByPriority(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT COALESCE(c.priority,\'normal\') AS p, '
          'COALESCE(SUM(t.amount_millimes),0) AS s '
          'FROM "transactions" t LEFT JOIN categories c '
          'ON c.id=t.category_id '
          'WHERE t.type=? AND t.occurred_at>=? AND t.occurred_at<? '
          'GROUP BY p',
          variables: [
            Variable.withString('expense'),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
          ],
        )
        .get();
    return {
      for (final r in rows)
        (r.data['p'] as String?) ?? 'normal':
            (r.data['s'] as num?)?.toInt() ?? 0,
    };
  }

  /// Oldest-first monthly slices. With [includeCurrent], the last slice is
  /// the partial current month; otherwise the last [monthsBack] COMPLETED
  /// months (use for averages).
  Future<List<MonthSlice>> monthlySeries({
    required DateTime now,
    required int monthsBack,
    bool includeCurrent = true,
  }) async {
    final months = <({int year, int month})>[];
    if (includeCurrent) {
      months.add((year: now.year, month: now.month));
      months.insertAll(0, Periods.lastCompletedMonths(now, monthsBack - 1));
    } else {
      months.addAll(Periods.lastCompletedMonths(now, monthsBack));
    }
    final out = <MonthSlice>[];
    for (final m in months) {
      final sums = await db.monthSums(m.year, m.month);
      out.add((
        year: m.year,
        month: m.month,
        income: sums.income,
        expense: sums.expense,
      ));
    }
    return out;
  }

  /// Per-day expense totals in [start, end). One indexed SUM per day —
  /// no full transaction scan. Caller picks max for highest-day.
  Future<Map<DateTime, int>> dailyExpenseTotals(
    DateTime start,
    DateTime end,
  ) async {
    final out = <DateTime, int>{};
    var day = Periods.dayStart(start);
    while (day.isBefore(end)) {
      out[day] = await _sum('expense', day, day.add(const Duration(days: 1)));
      day = day.add(const Duration(days: 1));
    }
    return out;
  }
}
