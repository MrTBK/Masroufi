import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

class TxnFilter {
  final String? search;
  final String? walletId;
  // Matches any of these wallets (transfer-aware: either endpoint).
  // When non-empty it takes precedence over [walletId].
  final List<String>? walletIds;
  final String? categoryId;
  // Matches any of these categories (e.g. parent + children rollup).
  // When non-empty it takes precedence over [categoryId].
  final List<String>? categoryIds;
  final String? type; // expense | income | transfer
  final DateTime? from;
  final DateTime? to;
  final int limit;
  final int offset;
  const TxnFilter({
    this.search,
    this.walletId,
    this.walletIds,
    this.categoryId,
    this.categoryIds,
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
    final walletIds = (f.walletIds != null && f.walletIds!.isNotEmpty)
        ? f.walletIds!
        : (f.walletId == null ? null : [f.walletId!]);
    if (walletIds != null) {
      q.where(
        (t) =>
            t.walletId.isIn(walletIds) |
            (t.type.equals('transfer') & t.toWalletId.isIn(walletIds)),
      );
    }
    if (f.categoryIds != null && f.categoryIds!.isNotEmpty) {
      q.where((t) => t.categoryId.isIn(f.categoryIds!));
    } else if (f.categoryId != null) {
      q.where((t) => t.categoryId.equals(f.categoryId!));
    }
    if (f.from != null) {
      q.where((t) => t.occurredAt.isBiggerOrEqualValue(f.from!));
    }
    if (f.to != null) {
      q.where((t) => t.occurredAt.isSmallerThanValue(f.to!));
    }
    if (f.search != null && f.search!.trim().isNotEmpty) {
      final needle = f.search!.trim();
      // Amount search: "12.5" jumps to the exact 12500-millime rows.
      // Category/wallet NAME matching is resolved to id lists by the
      // caller (timeline already holds both tables) and passed via
      // categoryIds/walletIds — no JOINs in the hot query.
      int? amountNeedle;
      try {
        amountNeedle = Money.parse(needle);
      } catch (_) {
        amountNeedle = null;
      }
      if (amountNeedle != null) {
        final amount = amountNeedle;
        q.where(
          (t) => t.note.contains(needle) | t.amountMillimes.equals(amount),
        );
      } else {
        q.where((t) => t.note.contains(needle));
      }
    }
  }

  Future<Transaction?> get(String id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Exact restore for undo: reinserts [t] with its ORIGINAL id and
  /// timestamps (upsert so a double-undo can never duplicate).
  /// The ledger is byte-identical to before the delete (incl. v8
  /// original-amount/currency).
  Future<void> restore(Transaction t) => db
      .into(db.transactions)
      .insertOnConflictUpdate(
        TransactionsCompanion(
          id: Value(t.id),
          type: Value(t.type),
          amountMillimes: Value(t.amountMillimes),
          walletId: Value(t.walletId),
          toWalletId: Value(t.toWalletId),
          categoryId: Value(t.categoryId),
          recurringRuleId: Value(t.recurringRuleId),
          origMinor: Value(t.origMinor),
          origCurrency: Value(t.origCurrency),
          occurredAt: Value(t.occurredAt),
          note: Value(t.note),
          createdAt: Value(t.createdAt),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<String> addExpense({
    required int amountMillimes,
    required String walletId,
    String? categoryId,
    DateTime? when,
    String note = '',
    int? origMinor,
    String? origCurrency,
  }) => _insert(
    'expense',
    amountMillimes,
    walletId,
    null,
    categoryId,
    when,
    note,
    origMinor: origMinor,
    origCurrency: origCurrency,
  );

  Future<String> addIncome({
    required int amountMillimes,
    required String walletId,
    String? categoryId,
    DateTime? when,
    String note = '',
    int? origMinor,
    String? origCurrency,
  }) => _insert(
    'income',
    amountMillimes,
    walletId,
    null,
    categoryId,
    when,
    note,
    origMinor: origMinor,
    origCurrency: origCurrency,
  );

  /// Single atomic row; counted in neither income nor expense.
  Future<String> addTransfer({
    required int amountMillimes,
    required String fromWalletId,
    required String toWalletId,
    DateTime? when,
    String note = '',
    int? origMinor,
    String? origCurrency,
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
      origMinor: origMinor,
      origCurrency: origCurrency,
    );
  }

  Future<String> _insert(
    String type,
    int amount,
    String walletId,
    String? toWalletId,
    String? categoryId,
    DateTime? when,
    String note, {
    int? origMinor,
    String? origCurrency,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be positive');
    if ((origMinor == null) != (origCurrency == null)) {
      throw ArgumentError('origMinor + origCurrency travel together');
    }
    if (origMinor != null && origMinor <= 0) {
      throw ArgumentError('orig amount must be positive');
    }
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
            origMinor: Value(origMinor),
            origCurrency: Value(origCurrency?.toUpperCase()),
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
    int? origMinor,
    String? origCurrency,
    bool clearOrig = false,
  }) => (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(
      amountMillimes: amountMillimes == null
          ? const Value.absent()
          : Value(amountMillimes),
      walletId: walletId == null ? const Value.absent() : Value(walletId),
      toWalletId: toWalletId == null ? const Value.absent() : Value(toWalletId),
      categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
      origMinor: clearOrig
          ? const Value(null)
          : (origMinor == null
                ? const Value.absent()
                : Value(origMinor)),
      origCurrency: clearOrig
          ? const Value(null)
          : (origCurrency == null
                ? const Value.absent()
                : Value(origCurrency.toUpperCase())),
      occurredAt: when == null ? const Value.absent() : Value(when),
      note: note == null ? const Value.absent() : Value(note.trim()),
      updatedAt: Value(DateTime.now()),
    ),
  );

  /// Distinct category ids ordered by most-recent use (expense/income
  /// only; transfers carry no category). Powers the quick-add "Recent"
  /// row: purely history-driven, never invented.
  Future<List<String>> recentCategoryIds({
    required String type,
    int limit = 6,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT category_id AS c, MAX(occurred_at) AS m FROM "transactions" '
          'WHERE type=? AND category_id IS NOT NULL '
          'GROUP BY category_id ORDER BY m DESC LIMIT ?',
          variables: [Variable.withString(type), Variable.withInt(limit)],
        )
        .get();
    return [for (final r in rows) r.data['c'] as String];
  }

  /// Distinct category ids ordered by use frequency over the last [days].
  /// Ties break by recency. Deterministic quick-add signal.
  Future<List<String>> frequentCategoryIds({
    required String type,
    int days = 30,
    int limit = 6,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await db
        .customSelect(
          'SELECT category_id AS c, COUNT(*) AS n, MAX(occurred_at) AS m '
          'FROM "transactions" '
          'WHERE type=? AND category_id IS NOT NULL AND occurred_at>=? '
          'GROUP BY category_id ORDER BY n DESC, m DESC LIMIT ?',
          variables: [
            Variable.withString(type),
            Variable.withDateTime(since),
            Variable.withInt(limit),
          ],
        )
        .get();
    return [for (final r in rows) r.data['c'] as String];
  }

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
