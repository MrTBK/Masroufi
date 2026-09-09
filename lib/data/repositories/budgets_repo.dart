import 'package:drift/drift.dart';

import '../../core/money/calc.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

class BudgetsRepo {
  final AppDb db;
  BudgetsRepo(this.db);

  Future<Budget?> getMonth(int year, int month) =>
      (db.select(db.budgets)
            ..where((b) => b.year.equals(year) & b.month.equals(month)))
          .getSingleOrNull();

  Stream<Budget?> watchMonth(int year, int month) =>
      (db.select(db.budgets)
            ..where((b) => b.year.equals(year) & b.month.equals(month)))
          .watchSingleOrNull();

  Future<void> upsert(int year, int month, int amountMillimes) async {
    if (amountMillimes <= 0) throw ArgumentError('budget must be positive');
    final existing = await getMonth(year, month);
    final now = DateTime.now();
    if (existing == null) {
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion(
              id: Value(newId()),
              year: Value(year),
              month: Value(month),
              amountMillimes: Value(amountMillimes),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.budgets,
      )..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(
          amountMillimes: Value(amountMillimes),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> remove(int year, int month) async {
    final existing = await getMonth(year, month);
    if (existing != null) {
      await (db.delete(
        db.budgets,
      )..where((b) => b.id.equals(existing.id))).go();
    }
  }

  /// Copy last month's overall budget into [year]/[month], idempotent:
  /// inserts only when the target has no budget, never overwrites.
  /// Returns true when a copy happened. Month-boundary safe.
  Future<bool> copyFromPrev(int year, int month) async {
    if (await getMonth(year, month) != null) return false;
    final prev = month == 1
        ? await getMonth(year - 1, 12)
        : await getMonth(year, month - 1);
    if (prev == null) return false;
    await upsert(year, month, prev.amountMillimes);
    return true;
  }

  /// Spent = expense sums for the month (transfers excluded).
  Future<int> spent(int year, int month) =>
      db.monthSums(year, month).then((s) => s.expense);

  Future<({int spent, int remaining, double pct})> status(
    int year,
    int month,
  ) async {
    final b = await getMonth(year, month);
    if (b == null) return (spent: 0, remaining: 0, pct: 0.0);
    final s = await spent(year, month);
    return (
      spent: s,
      remaining: FinanceCalc.budgetRemaining(
        budgetMillimes: b.amountMillimes,
        spentMillimes: s,
      ),
      pct: FinanceCalc.budgetUsedPct(
        budgetMillimes: b.amountMillimes,
        spentMillimes: s,
      ),
    );
  }
}
