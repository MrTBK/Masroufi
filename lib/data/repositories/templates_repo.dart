import 'package:drift/drift.dart';

import '../../core/utils/utils.dart';
import '../database/app_db.dart';

/// Transaction templates (v7): named prefilled drafts.
/// Applying a template ONLY prefills the txn form — it never writes to
/// the ledger by itself. Refs are plain text (no FK): deleting a wallet
/// or category orphans the ref, and the form falls back to "pick again".
class TemplatesRepo {
  final AppDb db;
  TemplatesRepo(this.db);

  Stream<List<TxnTemplate>> watch() {
    final q = db.select(db.txnTemplates)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return q.watch();
  }

  Future<List<TxnTemplate>> all() {
    final q = db.select(db.txnTemplates)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return q.get();
  }

  Future<TxnTemplate?> get(String id) =>
      (db.select(db.txnTemplates)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<String> create({
    required String name,
    required String type,
    required int amountMillimes,
    String? walletId,
    String? toWalletId,
    String? categoryId,
    String note = '',
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('name required');
    if (type != 'expense' && type != 'income' && type != 'transfer') {
      throw ArgumentError('bad type');
    }
    if (amountMillimes <= 0) throw ArgumentError('amount must be positive');
    if (type == 'transfer' &&
        (walletId == null ||
            toWalletId == null ||
            walletId == toWalletId)) {
      throw ArgumentError('transfer needs two distinct wallets');
    }
    final id = newId();
    final maxOrder =
        await (db.selectOnly(db.txnTemplates)
              ..addColumns([db.txnTemplates.sortOrder.max()]))
            .getSingleOrNull();
    final next = ((maxOrder?.read(db.txnTemplates.sortOrder.max())) ?? -1) + 1;
    final now = DateTime.now();
    await db
        .into(db.txnTemplates)
        .insert(
          TxnTemplatesCompanion(
            id: Value(id),
            name: Value(name.trim()),
            type: Value(type),
            amountMillimes: Value(amountMillimes),
            walletId: Value(walletId),
            toWalletId: Value(toWalletId),
            categoryId: Value(categoryId),
            note: Value(note.trim()),
            sortOrder: Value(next),
            createdAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) {
    if (name.trim().isEmpty) throw ArgumentError('name required');
    return (db.update(
      db.txnTemplates,
    )..where((t) => t.id.equals(id))).write(
      TxnTemplatesCompanion(name: Value(name.trim())),
    );
  }

  Future<void> remove(String id) =>
      (db.delete(db.txnTemplates)..where((t) => t.id.equals(id))).go();

  /// Move [id] one step in sort order (delta<0 up, >0 down). Swaps
  /// sortOrder with the neighbour; no-op at edges. Powers template
  /// reorder UI (Track 3); `rename()` already existed.
  Future<void> move(String id, int delta) async {
    if (delta == 0) return;
    final allCats = await all();
    final me = allCats.where((t) => t.id == id).firstOrNull;
    if (me == null) return;
    final sorted = [...allCats]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final i = sorted.indexWhere((t) => t.id == id);
    final j = (i + (delta < 0 ? -1 : 1)).clamp(0, sorted.length - 1);
    if (i == j) return;
    final other = sorted[j];
    await (db.update(
      db.txnTemplates,
    )..where((t) => t.id.equals(id))).write(
      TxnTemplatesCompanion(sortOrder: Value(other.sortOrder)),
    );
    await (db.update(
      db.txnTemplates,
    )..where((t) => t.id.equals(other.id))).write(
      TxnTemplatesCompanion(sortOrder: Value(me.sortOrder)),
    );
  }
}
