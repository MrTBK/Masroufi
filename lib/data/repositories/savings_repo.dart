import 'package:drift/drift.dart';

import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Savings goals. Contributions form a SEPARATE ledger: adding money to a
/// goal never creates wallet transactions, so ordinary balances cannot be
/// corrupted. Current amount = sum of contributions (int millimes).
class SavingsRepo {
  final AppDb db;
  SavingsRepo(this.db);

  Stream<List<SavingsGoal>> watch({bool includeArchived = false}) {
    final q = db.select(db.savingsGoals)
      ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]);
    if (!includeArchived) q.where((g) => g.isArchived.equals(false));
    return q.watch();
  }

  Future<List<SavingsGoal>> all({bool includeArchived = true}) {
    final q = db.select(db.savingsGoals)
      ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]);
    if (!includeArchived) q.where((g) => g.isArchived.equals(false));
    return q.get();
  }

  Future<SavingsGoal?> get(String id) => (db.select(
    db.savingsGoals,
  )..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<String> create({
    required String name,
    required int targetMillimes,
    DateTime? targetDate,
    String? walletId,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('name required');
    if (targetMillimes <= 0) throw ArgumentError('target must be positive');
    final id = newId();
    final now = DateTime.now();
    await db
        .into(db.savingsGoals)
        .insert(
          SavingsGoalsCompanion(
            id: Value(id),
            name: Value(name.trim()),
            targetMillimes: Value(targetMillimes),
            targetDate: Value(targetDate),
            walletId: Value(walletId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) =>
      (db.update(db.savingsGoals)..where((g) => g.id.equals(id))).write(
        SavingsGoalsCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setArchived(String id, bool archived) =>
      (db.update(db.savingsGoals)..where((g) => g.id.equals(id))).write(
        SavingsGoalsCompanion(
          isArchived: Value(archived),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> remove(String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.savingsContributions,
      )..where((c) => c.goalId.equals(id))).go();
      await (db.delete(db.savingsGoals)..where((g) => g.id.equals(id))).go();
    });
  }

  /// Positive = contribution, negative = withdrawal.
  Future<void> addContribution(
    String goalId,
    int amountMillimes, {
    DateTime? when,
    String note = '',
  }) async {
    if (amountMillimes == 0) throw ArgumentError('amount must be non-zero');
    final now = DateTime.now();
    await db
        .into(db.savingsContributions)
        .insert(
          SavingsContributionsCompanion(
            id: Value(newId()),
            goalId: Value(goalId),
            amountMillimes: Value(amountMillimes),
            occurredAt: Value(when ?? now),
            note: Value(note.trim()),
            createdAt: Value(now),
          ),
        );
  }

  Future<int> currentAmount(String goalId) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM savings_contributions WHERE goal_id=?',
          variables: [Variable.withString(goalId)],
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  Future<List<SavingsContribution>> history(String goalId) =>
      (db.select(db.savingsContributions)
            ..where((c) => c.goalId.equals(goalId))
            ..orderBy([(c) => OrderingTerm.desc(c.occurredAt)]))
          .get();

  static double progress(int currentMillimes, int targetMillimes) {
    if (targetMillimes <= 0) return 0;
    return (currentMillimes / targetMillimes).clamp(0.0, 1.0);
  }
}
