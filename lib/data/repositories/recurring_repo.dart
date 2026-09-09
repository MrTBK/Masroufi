import 'package:drift/drift.dart';

import '../../core/money/recurring.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Persistence for recurring rules. Date math lives in [Recurring];
/// generation is atomic so duplicates can never be silently created.
class RecurringRepo {
  final AppDb db;
  RecurringRepo(this.db);

  Stream<List<RecurringRule>> watch({bool activeOnly = false}) {
    final q = db.select(db.recurringRules)
      ..orderBy([(r) => OrderingTerm.asc(r.nextOccurrence)]);
    if (activeOnly) q.where((r) => r.isActive.equals(true));
    return q.watch();
  }

  Future<List<RecurringRule>> all({bool activeOnly = false}) {
    final q = db.select(db.recurringRules)
      ..orderBy([(r) => OrderingTerm.asc(r.nextOccurrence)]);
    if (activeOnly) q.where((r) => r.isActive.equals(true));
    return q.get();
  }

  Future<String> create({
    required String type, // expense | income
    required int amountMillimes,
    required String walletId,
    String? categoryId,
    String note = '',
    required String frequency,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    if (amountMillimes <= 0) throw ArgumentError('amount must be positive');
    if (!Recurring.frequencies.contains(frequency)) {
      throw ArgumentError('bad frequency');
    }
    final id = newId();
    final now = DateTime.now();
    await db
        .into(db.recurringRules)
        .insert(
          RecurringRulesCompanion(
            id: Value(id),
            type: Value(type),
            amountMillimes: Value(amountMillimes),
            walletId: Value(walletId),
            categoryId: Value(categoryId),
            note: Value(note.trim()),
            frequency: Value(frequency),
            startDate: Value(startDate),
            endDate: Value(endDate),
            nextOccurrence: Value(startDate),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateRule(
    String id, {
    int? amountMillimes,
    String? walletId,
    String? categoryId,
    String? note,
    String? frequency,
    DateTime? endDate,
    bool? isActive,
  }) => (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
    RecurringRulesCompanion(
      amountMillimes: amountMillimes == null
          ? const Value.absent()
          : Value(amountMillimes),
      walletId: walletId == null ? const Value.absent() : Value(walletId),
      categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
      note: note == null ? const Value.absent() : Value(note.trim()),
      frequency: frequency == null ? const Value.absent() : Value(frequency),
      endDate: endDate == null ? const Value.absent() : Value(endDate),
      isActive: isActive == null ? const Value.absent() : Value(isActive),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> remove(String id) =>
      (db.delete(db.recurringRules)..where((r) => r.id.equals(id))).go();

  /// Skip the current due occurrence (no transaction created).
  Future<void> skipOccurrence(String id) async {
    final rule = await (db.select(
      db.recurringRules,
    )..where((r) => r.id.equals(id))).getSingle();
    final next = Recurring.nextAfter(rule.nextOccurrence, rule.frequency);
    await (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(
        nextOccurrence: Value(next),
        lastGenerated: Value(rule.nextOccurrence),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Materialize every due occurrence up to [now]. Each insert and the
  /// next-occurrence advance happen in ONE transaction: reruns are safe and
  /// duplicates impossible. Returns created transaction ids.
  Future<List<String>> generateDue({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final created = <String>[];
    final rules = await all(activeOnly: true);
    for (final rule in rules) {
      var next = rule.nextOccurrence;
      var guard = 0;
      while (!next.isAfter(at) &&
          (rule.endDate == null || !next.isAfter(rule.endDate!)) &&
          guard++ < 1000) {
        final txnId = newId();
        final stamp = DateTime.now();
        await db.transaction(() async {
          await db
              .into(db.transactions)
              .insert(
                TransactionsCompanion(
                  id: Value(txnId),
                  type: Value(rule.type),
                  amountMillimes: Value(rule.amountMillimes),
                  walletId: Value(rule.walletId),
                  categoryId: Value(rule.categoryId),
                  recurringRuleId: Value(rule.id),
                  occurredAt: Value(
                    DateTime(
                      next.year,
                      next.month,
                      next.day,
                      at.hour,
                      at.minute,
                    ),
                  ),
                  note: Value(rule.note),
                  createdAt: Value(stamp),
                  updatedAt: Value(stamp),
                ),
              );
          final following = Recurring.nextAfter(next, rule.frequency);
          await (db.update(
            db.recurringRules,
          )..where((r) => r.id.equals(rule.id))).write(
            RecurringRulesCompanion(
              nextOccurrence: Value(following),
              lastGenerated: Value(next),
              updatedAt: Value(DateTime.now()),
            ),
          );
        });
        created.add(txnId);
        next = Recurring.nextAfter(next, rule.frequency);
      }
    }
    return created;
  }

  /// Next [limit] upcoming occurrences across active rules (for §5.5).
  Future<List<({RecurringRule rule, DateTime date})>> upcoming({
    DateTime? from,
    int days = 30,
    int limit = 20,
  }) async {
    final start = from ?? DateTime.now();
    final end = start.add(Duration(days: days));
    final out = <({RecurringRule rule, DateTime date})>[];
    for (final rule in await all(activeOnly: true)) {
      final dates = Recurring.occurrencesBetween(
        start: rule.nextOccurrence.isBefore(rule.startDate)
            ? rule.startDate
            : rule.nextOccurrence,
        frequency: rule.frequency,
        from: start,
        to: end,
        end: rule.endDate,
        limit: limit,
      );
      for (final d in dates) {
        out.add((rule: rule, date: d));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out.take(limit).toList();
  }
}
