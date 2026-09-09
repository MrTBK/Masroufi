import 'package:drift/drift.dart';

import '../../core/money/calc.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Monthly per-category budgets. The overall budget in [BudgetsRepo] is
/// untouched. Spent = expense sums for (category, month), transfers excluded.
class CategoryBudgetsRepo {
  final AppDb db;
  CategoryBudgetsRepo(this.db);

  Future<CategoryBudget?> get(String categoryId, int year, int month) =>
      (db.select(db.categoryBudgets)..where(
            (b) =>
                b.categoryId.equals(categoryId) &
                b.year.equals(year) &
                b.month.equals(month),
          ))
          .getSingleOrNull();

  Future<List<CategoryBudget>> forMonth(int year, int month) => (db.select(
    db.categoryBudgets,
  )..where((b) => b.year.equals(year) & b.month.equals(month))).get();

  Future<void> upsert(
    String categoryId,
    int year,
    int month,
    int amountMillimes,
  ) async {
    if (amountMillimes <= 0) throw ArgumentError('budget must be positive');
    final existing = await get(categoryId, year, month);
    final now = DateTime.now();
    if (existing == null) {
      await db
          .into(db.categoryBudgets)
          .insert(
            CategoryBudgetsCompanion(
              id: Value(newId()),
              categoryId: Value(categoryId),
              year: Value(year),
              month: Value(month),
              amountMillimes: Value(amountMillimes),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.categoryBudgets,
      )..where((b) => b.id.equals(existing.id))).write(
        CategoryBudgetsCompanion(
          amountMillimes: Value(amountMillimes),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> remove(String categoryId, int year, int month) async {
    final existing = await get(categoryId, year, month);
    if (existing != null) {
      await (db.delete(
        db.categoryBudgets,
      )..where((b) => b.id.equals(existing.id))).go();
    }
  }

  /// Copy last month's per-category budgets into [year]/[month].
  /// Idempotent batch upsert: only missing (category, month) cells are
  /// inserted; existing targets are never overwritten. Returns the number
  /// of rows copied. Month-boundary safe (Jan → Dec prior year).
  Future<int> copyFromPrev(int year, int month) async {
    final py = month == 1 ? year - 1 : year;
    final pm = month == 1 ? 12 : month - 1;
    final prev = await forMonth(py, pm);
    var copied = 0;
    for (final b in prev) {
      if (await get(b.categoryId, year, month) == null) {
        await upsert(b.categoryId, year, month, b.amountMillimes);
        copied++;
      }
    }
    return copied;
  }

  /// Spent for a category in a month. Parent budgets roll up children:
  /// transactions on the parent itself plus all direct children count.
  Future<int> spent(String categoryId, int year, int month) async {
    final (start: start, end: end) = AppDb.monthRange(year, month);
    final kids = await (db.select(
      db.categories,
    )..where((c) => c.parentId.equals(categoryId))).get();
    final ids = [categoryId, for (final k in kids) k.id];
    final placeholders = List.filled(ids.length, '?').join(',');
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM "transactions" '
          'WHERE type=? AND category_id IN ($placeholders) '
          'AND occurred_at>=? AND occurred_at<?',
          variables: [
            Variable.withString('expense'),
            for (final id in ids) Variable.withString(id),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
          ],
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  Future<({int spent, int remaining, double pct})> status(
    String categoryId,
    int year,
    int month,
  ) async {
    final b = await get(categoryId, year, month);
    if (b == null) return (spent: 0, remaining: 0, pct: 0.0);
    final s = await spent(categoryId, year, month);
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
