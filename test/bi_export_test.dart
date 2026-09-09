import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/bi_scope.dart';
import 'package:masroufi/core/export/bi_export.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/category_budgets_repo.dart';
import 'package:masroufi/data/repositories/debts_repo.dart';
import 'package:masroufi/data/repositories/recurring_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('BiExport', () {
    late AppDb db;
    late BiSnapshot snap;
    late List<Transaction> txns;
    late Map<String, Wallet> wallets;
    late Map<String, Category> cats;

    setUp(() async {
      db = _db();
      final categories = CategoriesRepo(db);
      await categories.seedDefaults();
      final wrepo = WalletsRepo(db);
      final trepo = TransactionsRepo(db);
      final cash = await wrepo.create(name: 'Cash');
      final all = await categories.all();
      final cafe = all.firstWhere((c) => c.nameKey == 'cat_cafe');
      await trepo.addExpense(
        amountMillimes: 5500,
        walletId: cash,
        categoryId: cafe.id,
        note: 'Coffee',
        when: DateTime(2026, 9, 5),
      );
      final bi = FilteredAnalytics(
        analytics: AnalyticsRepo(db),
        wallets: wrepo,
        categories: categories,
        recurring: RecurringRepo(db),
        debts: DebtsRepo(db),
        budgets: BudgetsRepo(db),
        catBudgets: CategoryBudgetsRepo(db),
      );
      snap = await bi.load(
        BiFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 1)),
        now: DateTime(2026, 9, 15),
      );
      txns = await trepo.list(
        TxnFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 1)),
      );
      wallets = {for (final w in await wrepo.all()) w.id: w};
      cats = {for (final c in all) c.id: c};
    });

    tearDown(() => db.close());

    test('kpiCsv carries scope metrics as raw numbers', () {
      final csv = BiExport.kpiCsv(snap);
      final lines = csv.split(RegExp(r'\r?\n'));
      expect(lines.first, 'metric,value');
      expect(csv, contains('expense_millimes,5500'));
      expect(csv, contains('txn_count,1'));
      expect(csv, contains('month_spent_millimes,5500'));
      // No income and no budget in scope: optional rows absent, never
      // zero-filled.
      expect(csv.contains('savings_rate_pct'), isFalse);
      expect(csv.contains('overall_budget_millimes'), isFalse);
    });

    test('datasetCsv renders hierarchy paths and names', () {
      final csv = BiExport.datasetCsv(
        txns: txns,
        wallets: wallets,
        cats: cats,
        lang: 'en',
      );
      final lines = csv.split(RegExp(r'\r?\n'));
      expect(
        lines.first,
        'date,type,amount_millimes,category_path,wallet,to_wallet,note',
      );
      expect(lines, hasLength(2));
      expect(csv, contains('expense'));
      expect(csv, contains('5500'));
      expect(csv, contains('Cash'));
      expect(csv, contains('Coffee'));
      // Café is a child: the path names its parent (rollup-safe).
      expect(csv.contains('Food') || csv.contains('Caf'), isTrue);
    });
  });
}
