import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/category_budgets_repo.dart';
import 'package:masroufi/data/repositories/debts_repo.dart';
import 'package:masroufi/data/repositories/savings_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

void main() {
  late AppDb db;
  late WalletsRepo wallets;
  late TransactionsRepo txns;
  late CategoryBudgetsRepo catBudgets;
  late SavingsRepo savings;
  late DebtsRepo debts;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    wallets = WalletsRepo(db);
    txns = TransactionsRepo(db);
    catBudgets = CategoryBudgetsRepo(db);
    savings = SavingsRepo(db);
    debts = DebtsRepo(db);
  });
  tearDown(() => db.close());

  group('category budgets', () {
    test('spent/remaining/pct with over-budget', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 1000000);
      const cat = 'cat_food_test';
      final now = DateTime.now();
      await txns.addExpense(
        amountMillimes: 390000,
        walletId: cash,
        categoryId: cat,
      );
      await catBudgets.upsert(cat, now.year, now.month, 300000);
      final s = await catBudgets.status(cat, now.year, now.month);
      expect(s.spent, 390000);
      expect(s.remaining, -90000);
      expect(s.pct, closeTo(1.3, 1e-9));
    });

    test('transfers do not count as category spend', () async {
      final a = await wallets.create(name: 'A', initialMillimes: 500000);
      final b = await wallets.create(name: 'B', initialMillimes: 0);
      const cat = 'cat_x';
      await txns.addTransfer(
        amountMillimes: 100000,
        fromWalletId: a,
        toWalletId: b,
      );
      final now = DateTime.now();
      await catBudgets.upsert(cat, now.year, now.month, 50000);
      expect(await catBudgets.spent(cat, now.year, now.month), 0);
    });
  });

  group('savings goals', () {
    test(
      'contributions sum, withdrawals subtract, wallets untouched',
      () async {
        final cash = await wallets.create(
          name: 'Cash',
          initialMillimes: 100000,
        );
        final goal = await savings.create(
          name: 'Emergency Fund',
          targetMillimes: 2000000,
        );
        await savings.addContribution(goal, 1000000);
        await savings.addContribution(goal, 250000);
        await savings.addContribution(goal, -50000);
        expect(await savings.currentAmount(goal), 1200000);
        expect(SavingsRepo.progress(1200000, 2000000), 0.6);
        // Ordinary balance unchanged: separate ledger.
        final w = await wallets.get(cash);
        expect(await wallets.balance(w!), 100000);
        expect(await savings.history(goal), hasLength(3));
      },
    );
  });

  group('debts', () {
    test(
      'owed-to-me: partial payments, auto-settle, single counting',
      () async {
        final cash = await wallets.create(name: 'Cash', initialMillimes: 0);
        final id = await debts.create(
          person: 'Ahmed',
          direction: 'owed',
          originalMillimes: 50000,
        );
        await debts.pay(debtId: id, amountMillimes: 20000, walletId: cash);
        expect(await debts.paid(id), 20000);
        expect(await debts.remaining(id), 30000);
        // Repayment arrived as income exactly once.
        final w = await wallets.get(cash);
        expect(await wallets.balance(w!), 20000);
        final sums = await db.monthSums(
          DateTime.now().year,
          DateTime.now().month,
        );
        expect(sums.income, 20000);
        expect(sums.expense, 0);
        // Second payment settles.
        await debts.pay(debtId: id, amountMillimes: 30000, walletId: cash);
        expect((await debts.get(id))!.status, 'settled');
        expect(await debts.history(id), hasLength(2));
      },
    );

    test('money I owe pays as expense; overpayment rejected', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 100000);
      final id = await debts.create(
        person: 'Sara',
        direction: 'owe',
        originalMillimes: 40000,
      );
      await expectLater(
        debts.pay(debtId: id, amountMillimes: 50000, walletId: cash),
        throwsArgumentError,
      );
      await debts.pay(debtId: id, amountMillimes: 40000, walletId: cash);
      final w = await wallets.get(cash);
      expect(await wallets.balance(w!), 60000); // expense counted once
    });
  });
}
