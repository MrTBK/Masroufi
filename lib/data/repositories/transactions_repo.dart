import 'package:drift/drift.dart';

import '../../core/utils/utils.dart';
import '../database/app_db.dart';

class TxnFilter {
  final String? search;
  final String? walletId;
  final String? categoryId;
  final String? type; // expense | income | transfer
  final DateTime? from;
  final DateTime? to;
  final int limit;
  final int offset;
  const TxnFilter({
    this.search,
    this.walletId,
    this.categoryId,
    this.type,
    this.from,
    this.to,
    this.limit = 100,
    this.offset = 0,
  });
}

class TransactionsRepo {
  final AppDb db;
  TransactionsRepo(this.db);

  Stream<List<Transaction>> watch(TxnFilter f) {
    final q = db.select(db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    _apply(q, f);
    q.limit(f.limit, offset: f.offset);
    return q.watch();
  }

  Future<List<Transaction>> list(TxnFilter f) {
    final q = db.select(db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    _apply(q, f);
    q.limit(f.limit, offset: f.offset);
    return q.get();
  }

  void _apply(
    SimpleSelectStatement<$TransactionsTable, Transaction> q,
    TxnFilter f,
  ) {
    if (f.type != null) q.where((t) => t.type.equals(f.type!));
    if (f.walletId != null) {
      final w = f.walletId!;
      q.where(
        (t) =>
            t.walletId.equals(w) |
            (t.type.equals('transfer') & t.toWalletId.equals(w)),
      );
    }
    if (f.categoryId != null) {
      q.where((t) => t.categoryId.equals(f.categoryId!));
    }
    if (f.from != null) {
      q.where((t) => t.occurredAt.isBiggerOrEqualValue(f.from!));
    }
    if (f.to != null) {
      q.where((t) => t.occurredAt.isSmallerThanValue(f.to!));
    }
    if (f.search != null && f.search!.trim().isNotEmpty) {
      q.where((t) => t.note.contains(f.search!.trim()));
    }
  }

  Future<String> addExpense({
    required int amountMillimes,
    required String walletId,
    String? categoryId,
    DateTime? when,
    String note = '',
  }) => _insert(
    'expense',
    amountMillimes,
    walletId,
    null,
    categoryId,
    when,
    note,
  );

  Future<String> addIncome({
    required int amountMillimes,
    required String walletId,
    String? categoryId,
    DateTime? when,
    String note = '',
  }) =>
      _insert('income', amountMillimes, walletId, null, categoryId, when, note);

  /// Single atomic row; counted in neither income nor expense.
  Future<String> addTransfer({
    required int amountMillimes,
    required String fromWalletId,
    required String toWalletId,
    DateTime? when,
    String note = '',
  }) {
    assert(fromWalletId != toWalletId);
    return _insert(
      'transfer',
      amountMillimes,
      fromWalletId,
      toWalletId,
      null,
      when,
      note,
    );
  }

  Future<String> _insert(
    String type,
    int amount,
    String walletId,
    String? toWalletId,
    String? categoryId,
    DateTime? when,
    String note,
  ) async {
    if (amount <= 0) throw ArgumentError('amount must be positive');
    final id = newId();
    final now = DateTime.now();
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion(
            id: Value(id),
            type: Value(type),
            amountMillimes: Value(amount),
            walletId: Value(walletId),
            toWalletId: Value(toWalletId),
            categoryId: Value(categoryId),
            occurredAt: Value(when ?? now),
            note: Value(note.trim()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateTxn(
    String id, {
    int? amountMillimes,
    String? walletId,
    String? toWalletId,
    String? categoryId,
    DateTime? when,
    String? note,
  }) => (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(
      amountMillimes: amountMillimes == null
          ? const Value.absent()
          : Value(amountMillimes),
      walletId: walletId == null ? const Value.absent() : Value(walletId),
      toWalletId: toWalletId == null ? const Value.absent() : Value(toWalletId),
      categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
      occurredAt: when == null ? const Value.absent() : Value(when),
      note: note == null ? const Value.absent() : Value(note.trim()),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> delete(String id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  Future<String> duplicate(String id) async {
    final t = await (db.select(
      db.transactions,
    )..where((x) => x.id.equals(id))).getSingle();
    return _insert(
      t.type,
      t.amountMillimes,
      t.walletId,
      t.toWalletId,
      t.categoryId,
      DateTime.now(),
      t.note,
    );
  }
}
