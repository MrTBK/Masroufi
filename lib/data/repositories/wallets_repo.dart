import 'package:drift/drift.dart';

import '../../core/money/calc.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

class WalletsRepo {
  final AppDb db;
  WalletsRepo(this.db);

  Stream<List<Wallet>> watch({bool includeArchived = false}) {
    final q = db.select(db.wallets)
      ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]);
    if (!includeArchived) q.where((w) => w.isArchived.equals(false));
    return q.watch();
  }

  Future<List<Wallet>> all({bool includeArchived = true}) {
    final q = db.select(db.wallets)
      ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]);
    if (!includeArchived) q.where((w) => w.isArchived.equals(false));
    return q.get();
  }

  Future<Wallet?> get(String id) =>
      (db.select(db.wallets)..where((w) => w.id.equals(id))).getSingleOrNull();

  Future<String> create({
    required String name,
    String icon = 'cash',
    int initialMillimes = 0,
    String colorKey = 'teal',
    String design = 'classic',
  }) async {
    final id = newId();
    final now = DateTime.now();
    await db
        .into(db.wallets)
        .insert(
          WalletsCompanion(
            id: Value(id),
            name: Value(name.trim()),
            icon: Value(icon),
            initialMillimes: Value(initialMillimes),
            colorKey: Value(colorKey),
            design: Value(design),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String name) =>
      _touch(id, WalletsCompanion(name: Value(name.trim())));

  Future<void> setIcon(String id, String icon) =>
      _touch(id, WalletsCompanion(icon: Value(icon)));

  /// Card styling (display-only keys; never affects balances).
  Future<void> setColorKey(String id, String colorKey) =>
      _touch(id, WalletsCompanion(colorKey: Value(colorKey)));

  Future<void> setDesign(String id, String design) =>
      _touch(id, WalletsCompanion(design: Value(design)));

  Future<void> setArchived(String id, bool archived) =>
      _touch(id, WalletsCompanion(isArchived: Value(archived)));

  /// Presentation-only privacy flag. Balance math is untouched:
  /// hidden wallets stay included in every total.
  Future<void> setBalanceHidden(String id, bool hidden) =>
      _touch(id, WalletsCompanion(isBalanceHidden: Value(hidden)));

  Future<void> _touch(String id, WalletsCompanion patch) =>
      (db.update(db.wallets)..where((w) => w.id.equals(id))).write(
        patch.copyWith(updatedAt: Value(DateTime.now())),
      );

  /// Derived balance (never stored): initial + income - expense + tIn - tOut.
  Future<int> balance(Wallet w) async {
    final f = await db.walletFlows(w.id);
    return FinanceCalc.walletBalance(
      initialMillimes: w.initialMillimes,
      incomeMillimes: f.income,
      expenseMillimes: f.expense,
      transfersInMillimes: f.tIn,
      transfersOutMillimes: f.tOut,
    );
  }

  Future<int> totalBalance() async {
    var total = 0;
    for (final w in await all(includeArchived: false)) {
      total += await balance(w);
    }
    return total;
  }

  /// Display-only "your money": like [totalBalance] but EXCLUDING hidden
  /// wallets so a hidden balance can never leak through a prominent
  /// summary by subtraction. Archived wallets are excluded too.
  /// Ledger math is untouched: use [totalBalance] for real accounting.
  Future<int> visibleBalance() async {
    var total = 0;
    for (final w in await all(includeArchived: false)) {
      if (w.isBalanceHidden) continue;
      total += await balance(w);
    }
    return total;
  }
}
