import 'package:drift/drift.dart';

import '../../data/database/app_db.dart';

/// Net-worth trend (Track 7, no schema).
///
/// Documented formula (never relabeled):
/// worth(monthEnd) = Σ visible wallet initials
///   + Σ income(occurredAt < monthEnd)
///   − Σ expense(occurredAt < monthEnd)
///   + Σ transferIn(< monthEnd) − Σ transferOut(< monthEnd)
///   + Σ savings contributions(occurredAt < monthEnd, non-archived goals).
///
/// Visible = non-archived AND non-hidden wallets (display-level, so hidden
/// money never leaks; ledger math still uses all wallets elsewhere).
/// Savings are included because they are user wealth even though the
/// ledger keeps them separate. All int millimes.
typedef WorthPoint = ({int year, int month, int worth});

abstract final class NetWorth {
  /// Pure trend assembly from precomputed points (sorts oldest-first).
  static List<WorthPoint> buildTrend(List<WorthPoint> points) {
    final sorted = [...points]
      ..sort((a, b) {
        final c = a.year.compareTo(b.year);
        return c != 0 ? c : a.month.compareTo(b.month);
      });
    return sorted;
  }

  /// Pure delta between last two points (null when <2 points).
  static ({int diff, int pct})? delta(List<WorthPoint> trend) {
    if (trend.length < 2) return null;
    final prev = trend[trend.length - 2].worth;
    final cur = trend.last.worth;
    if (prev <= 0) return null;
    final diff = cur - prev;
    var pct = ((diff * 100).abs() + prev ~/ 2) ~/ prev;
    if (diff < 0) pct = -pct;
    return (diff: diff, pct: pct);
  }

  /// DB-backed trend: worth at each month-end for [monthsBack] months
  /// ending with [now]'s month. One batched set of SUMs per month.
  static Future<List<WorthPoint>> trend({
    required AppDb db,
    required DateTime now,
    int monthsBack = 6,
  }) async {
    Future<int> sum(String sql, List<Variable> vars) async {
      final row = await db.customSelect(sql, variables: vars).getSingleOrNull();
      return (row?.data.values.firstOrNull as num?)?.toInt() ?? 0;
    }

    final wallets = await (db.select(
      db.wallets,
    )..where((w) => w.isArchived.equals(false) & w.isBalanceHidden.equals(false))).get();
    final initial = wallets.fold(0, (a, w) => a + w.initialMillimes);
    final walletIds = wallets.map((w) => w.id).toList();
    final goals = await (db.select(
      db.savingsGoals,
    )..where((g) => g.isArchived.equals(false))).get();
    final goalIds = goals.map((g) => g.id).toList();

    // Month-ends oldest-first.
    final months = <({int year, int month, DateTime end})>[];
    var y = now.year;
    var m = now.month;
    for (var i = 0; i < monthsBack; i++) {
      final end = m == 12
          ? DateTime(y + 1, 1, 1)
          : DateTime(y, m + 1, 1);
      months.add((year: y, month: m, end: end));
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
    }
    final ordered = months.reversed.toList();
    final out = <WorthPoint>[];
    for (final mo in ordered) {
      final end = Variable.withDateTime(mo.end);
      var flows = 0;
      if (walletIds.isNotEmpty) {
        final inList = List.filled(walletIds.length, '?').join(',');
        flows += await sum(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND wallet_id IN ($inList) AND occurred_at<?',
          [
            Variable.withString('income'),
            for (final id in walletIds) Variable.withString(id),
            end,
          ],
        );
        flows -= await sum(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND wallet_id IN ($inList) AND occurred_at<?',
          [
            Variable.withString('expense'),
            for (final id in walletIds) Variable.withString(id),
            end,
          ],
        );
        flows += await sum(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND to_wallet_id IN ($inList) AND occurred_at<?',
          [
            Variable.withString('transfer'),
            for (final id in walletIds) Variable.withString(id),
            end,
          ],
        );
        flows -= await sum(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND wallet_id IN ($inList) AND occurred_at<?',
          [
            Variable.withString('transfer'),
            for (final id in walletIds) Variable.withString(id),
            end,
          ],
        );
      }
      var savings = 0;
      if (goalIds.isNotEmpty) {
        final gList = List.filled(goalIds.length, '?').join(',');
        savings = await sum(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s '
          'FROM savings_contributions WHERE goal_id IN ($gList) '
          'AND occurred_at<?',
          [
            for (final id in goalIds) Variable.withString(id),
            end,
          ],
        );
      }
      out.add((year: mo.year, month: mo.month, worth: initial + flows + savings));
    }
    return buildTrend(out);
  }
}
