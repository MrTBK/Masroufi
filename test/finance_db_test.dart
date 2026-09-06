import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

/// End-to-end MVP scenario against an in-memory DB:
/// wallet 100 -> -12.500 -> -8 -> +500 -> transfer 100 -> budget check.
void main() {
  late AppDb db;
  late WalletsRepo wallets;
  late TransactionsRepo txns;
  late BudgetsRepo budgets;
  late CategoriesRepo cats;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    wallets = WalletsRepo(db);
    txns = TransactionsRepo(db);
    budgets = BudgetsRepo(db);
    cats = CategoriesRepo(db);
  });

  tearDown(() => db.close());

  test('full MVP money flow with persistence in one session', () async {
    await cats.seedDefaults();
    expect(await cats.all(), isNotEmpty);

    final cashId = await wallets.create(name: 'Cash', initialMillimes: 100000);
    final bankId = await wallets.create(name: 'Bank', initialMillimes: 0);

    Future<int> balanceOf(String id) async {
      final w = await wallets.get(id);
      return wallets.balance(w!);
    }

    expect(await balanceOf(cashId), 100000);

    final allCats = await cats.all(includeArchived: false);
    final cafe = allCats.firstWhere((c) => c.nameKey == 'cat_cafe');

    await txns.addExpense(
      amountMillimes: 12500,
      walletId: cashId,
      categoryId: cafe.id,
    );
    expect(await balanceOf(cashId), 87500);

    await txns.addExpense(amountMillimes: 8000, walletId: cashId);
    expect(await balanceOf(cashId), 79500);

    await txns.addIncome(amountMillimes: 500000, walletId: cashId);
    expect(await balanceOf(cashId), 579500);

    // Transfer must not count as income/expense.
    await txns.addTransfer(
      amountMillimes: 100000,
      fromWalletId: cashId,
      toWalletId: bankId,
    );
    expect(await balanceOf(cashId), 479500);
    expect(await balanceOf(bankId), 100000);
    expect(await wallets.totalBalance(), 579500);

    final now = DateTime.now();
    final sums = await db.monthSums(now.year, now.month);
    expect(sums.income, 500000);
    expect(sums.expense, 20500); // transfer excluded

    await budgets.upsert(now.year, now.month, 250000);
    await txns.addExpense(amountMillimes: 50000, walletId: cashId);
    final status = await budgets.status(now.year, now.month);
    expect(status.spent, 70500);
    expect(status.remaining, 250000 - 70500);

    // Delete + edit paths.
    final all = await txns.list(const TxnFilter(limit: 5));
    expect(all, isNotEmpty);
    final dup = await txns.duplicate(all.first.id);
    expect(dup, isNotEmpty);
    await txns.delete(dup);
  });
}
