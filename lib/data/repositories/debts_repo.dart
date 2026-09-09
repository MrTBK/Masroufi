import 'package:drift/drift.dart';

import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Debts in both directions ('owe' | 'owed'). A payment is recorded as a
/// DebtPayments row AND its wallet movement as a real transaction
/// (expense when I pay someone I owe; income when someone repays me),
/// created atomically with the payment's [txnId] link. Wallet balances
/// therefore update exactly once through the normal ledger — never
/// double-counted, never bypassed.
class DebtsRepo {
  final AppDb db;
  DebtsRepo(this.db);

  Stream<List<Debt>> watch({bool openOnly = false}) {
    final q = db.select(db.debts)
      ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
    if (openOnly) q.where((d) => d.status.equals('open'));
    return q.watch();
  }

  Future<List<Debt>> all({bool openOnly = false}) {
    final q = db.select(db.debts)
      ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
    if (openOnly) q.where((d) => d.status.equals('open'));
    return q.get();
  }

  Future<Debt?> get(String id) =>
      (db.select(db.debts)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<String> create({
    required String person,
    required String direction, // owe | owed
    required int originalMillimes,
    DateTime? when,
    DateTime? dueDate,
    String notes = '',
  }) async {
    if (person.trim().isEmpty) throw ArgumentError('person required');
    if (direction != 'owe' && direction != 'owed') {
      throw ArgumentError('bad direction');
    }
    if (originalMillimes <= 0) throw ArgumentError('amount must be positive');
    final id = newId();
    final now = DateTime.now();
    await db
        .into(db.debts)
        .insert(
          DebtsCompanion(
            id: Value(id),
            person: Value(person.trim()),
            direction: Value(direction),
            originalMillimes: Value(originalMillimes),
            occurredAt: Value(when ?? now),
            dueDate: Value(dueDate),
            notes: Value(notes.trim()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateDebt(
    String id, {
    String? person,
    DateTime? dueDate,
    String? notes,
  }) => (db.update(db.debts)..where((d) => d.id.equals(id))).write(
    DebtsCompanion(
      person: person == null ? const Value.absent() : Value(person.trim()),
      dueDate: dueDate == null ? const Value.absent() : Value(dueDate),
      notes: notes == null ? const Value.absent() : Value(notes.trim()),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> remove(String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.debtPayments,
      )..where((p) => p.debtId.equals(id))).go();
      // Linked wallet transactions are ordinary history: keep them.
      await (db.delete(db.debts)..where((d) => d.id.equals(id))).go();
    });
  }

  /// Record a partial payment. Creates the wallet transaction + payment row
  /// atomically and auto-settles at zero remaining. Overpayment is rejected.
  Future<String> pay({
    required String debtId,
    required int amountMillimes,
    required String walletId,
    DateTime? when,
    String note = '',
  }) async {
    if (amountMillimes <= 0) throw ArgumentError('amount must be positive');
    final debt = await get(debtId);
    if (debt == null) throw ArgumentError('unknown debt');
    if (debt.status != 'open') throw StateError('debt already settled');
    final remaining = await this.remaining(debtId);
    if (amountMillimes > remaining) {
      throw ArgumentError('payment exceeds remaining');
    }
    final at = when ?? DateTime.now();
    final txnId = newId();
    final paymentId = newId();
    final stamp = DateTime.now();
    await db.transaction(() async {
      // Wallet movement through the normal ledger (single counting point).
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion(
              id: Value(txnId),
              type: Value(debt.direction == 'owe' ? 'expense' : 'income'),
              amountMillimes: Value(amountMillimes),
              walletId: Value(walletId),
              occurredAt: Value(at),
              note: Value(note.trim().isEmpty ? debt.person : note.trim()),
              createdAt: Value(stamp),
              updatedAt: Value(stamp),
            ),
          );
      await db
          .into(db.debtPayments)
          .insert(
            DebtPaymentsCompanion(
              id: Value(paymentId),
              debtId: Value(debtId),
              amountMillimes: Value(amountMillimes),
              walletId: Value(walletId),
              txnId: Value(txnId),
              occurredAt: Value(at),
              note: Value(note.trim()),
              createdAt: Value(stamp),
            ),
          );
      if (amountMillimes == remaining) {
        await (db.update(db.debts)..where((d) => d.id.equals(debtId))).write(
          DebtsCompanion(
            status: const Value('settled'),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
    return paymentId;
  }

  Future<int> paid(String debtId) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM debt_payments WHERE debt_id=?',
          variables: [Variable.withString(debtId)],
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  Future<int> remaining(String debtId) async {
    final debt = await get(debtId);
    if (debt == null) return 0;
    return debt.originalMillimes - await paid(debtId);
  }

  Future<List<DebtPayment>> history(String debtId) =>
      (db.select(db.debtPayments)
            ..where((p) => p.debtId.equals(debtId))
            ..orderBy([(p) => OrderingTerm.desc(p.occurredAt)]))
          .get();
}
