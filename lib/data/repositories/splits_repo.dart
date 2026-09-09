import 'package:drift/drift.dart';

import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Split-transaction lines (v8). The parent [Transactions] row is never
/// mutated by splits: its amount stays the source of truth for balances.
/// Invariant: SUM(splits for txn) == parent.amountMillimes (enforced on
/// write; violations throw). Plain-text refs, no FK.
class SplitsRepo {
  final AppDb db;
  SplitsRepo(this.db);

  Future<List<TxnSplit>> forTxn(String txnId) =>
      (db.select(db.txnSplits)..where((s) => s.txnId.equals(txnId))).get();

  Stream<List<TxnSplit>> watchTxn(String txnId) =>
      (db.select(db.txnSplits)..where((s) => s.txnId.equals(txnId))).watch();

  Future<int> totalFor(String txnId) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_millimes),0) AS s FROM txn_splits WHERE txn_id=?',
          variables: [Variable.withString(txnId)],
        )
        .getSingleOrNull();
    return (row?.data['s'] as num?)?.toInt() ?? 0;
  }

  /// Replace all splits for [txnId] with [lines] atomically. Validates:
  /// every amount > 0 and the sum equals the parent amount exactly.
  /// Throws [StateError] on invariant breach; writes nothing then.
  Future<void> setSplits(
    String txnId,
    List<({String? categoryId, int amountMillimes, String note})> lines,
  ) async {
    final parent =
        await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(txnId))).getSingleOrNull();
    if (parent == null) throw StateError('missing txn');
    if (lines.isEmpty) throw StateError('empty splits');
    var sum = 0;
    for (final l in lines) {
      if (l.amountMillimes <= 0) throw StateError('split amount');
      sum += l.amountMillimes;
    }
    if (sum != parent.amountMillimes) throw StateError('split sum != parent');
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.delete(
        db.txnSplits,
      )..where((s) => s.txnId.equals(txnId))).go();
      for (final l in lines) {
        await db
            .into(db.txnSplits)
            .insert(
              TxnSplitsCompanion(
                id: Value(newId()),
                txnId: Value(txnId),
                categoryId: Value(l.categoryId),
                amountMillimes: Value(l.amountMillimes),
                note: Value(l.note),
                createdAt: Value(now),
              ),
            );
      }
    });
  }

  Future<void> clearTxn(String txnId) =>
      (db.delete(db.txnSplits)..where((s) => s.txnId.equals(txnId))).go();
}
