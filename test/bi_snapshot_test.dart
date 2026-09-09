import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/bi_scope.dart';
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
  group('FilteredAnalytics.load', () {
    late AppDb db;
    late FilteredAnalytics bi;
    late TransactionsRepo txns;

    setUp(() async {
      db = _db();
      final analytics = AnalyticsRepo(db);
      final wallets = WalletsRepo(db);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      txns = TransactionsRepo(db);
      bi = FilteredAnalytics(
        analytics: analytics,
        wallets: wallets,
        categories: cats,
        recurring: RecurringRepo(db),
        debts: DebtsRepo(db),
        budgets: BudgetsRepo(db),
        catBudgets: CategoryBudgetsRepo(db),
      );
      final cash = await wallets.create(name: 'Cash');
      final bank = await wallets.create(name: 'Bank');
      // August baseline + September scope.
      await txns.addExpense(
        amountMillimes: 100000,
        walletId: cash,
        when: DateTime(2026, 8, 10),
      );
      await txns.addExpense(
        amountMillimes: 120000,
        walletId: cash,
        when: DateTime(2026, 9, 5),
      );
      await txns.addExpense(
        amountMillimes: 180000,
        walletId: bank,
        when: DateTime(2026, 9, 6),
      );
      await txns.addIncome(
        amountMillimes: 1000000,
        walletId: bank,
        when: DateTime(2026, 9, 7),
      );
      await BudgetsRepo(db).upsert(2026, 9, 500000);
    });

    tearDown(() => db.close());

    test('month scope computes KPIs, growth, YoY-null, budgets', () async {
      final s = await bi.load(
        BiFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 1)),
        now: DateTime(2026, 9, 15),
      );
      expect(s.income, 1000000);
      expect(s.expense, 300000);
      expect(s.txnCount, 3);
      expect(s.savingsRate, 70);
      expect(s.growth, (diff: 200000, pct: 200));
      // No 2025 data: YoY present but zero.
      expect(s.yoyExpense, 0);
      expect(s.overallBudget, 500000);
      expect(s.overallSpent, 300000);
      expect(s.trend, hasLength(6));
      expect(s.trend.last.expense, 300000);
      expect(s.incomeByCat.values.fold(0, (a, b) => a + b), 1000000);
      expect(s.byWallet.values.fold(0, (a, b) => a + b), 300000);
    });

    test('wallet filter narrows every figure', () async {
      final wallets = await WalletsRepo(db).all(includeArchived: false);
      final cash = wallets.firstWhere((w) => w.name == 'Cash').id;
      final s = await bi.load(
        BiFilter(
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 10, 1),
          walletIds: [cash],
        ),
        now: DateTime(2026, 9, 15),
      );
      expect(s.expense, 120000);
      expect(s.income, 0);
      expect(s.savingsRate, isNull);
      expect(s.txnCount, 1);
    });

    test('arbitrary range skips YoY; empty baseline yields null growth',
        () async {
      final s = await bi.load(
        BiFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 8)),
        now: DateTime(2026, 9, 15),
      );
      expect(s.yoyExpense, isNull);
      // Aug 25-Sep 1 baseline is empty: null-safe rule, not zero noise.
      expect(s.growth, isNull);
    });

    test('expandCategory maps parent to parent-plus-children', () async {
      final cats = await CategoriesRepo(db).all(includeArchived: true);
      final parent = cats.firstWhere((c) => c.parentId == null);
      final kids = cats.where((c) => c.parentId == parent.id).toList();
      expect(kids, isNotEmpty);
      final ids = BiFilter.expandCategory(cats, parent.id)!;
      expect(ids.first, parent.id);
      expect(ids.length, 1 + kids.length);
      expect(BiFilter.expandCategory(cats, null), isNull);
    });

    test('monthlyRuleEstimate normalizes frequencies', () async {
      final db2 = _db();
      RecurringRule mk(String f, int amt) {
        return RecurringRule(
          id: 'x',
          type: 'expense',
          amountMillimes: amt,
          walletId: 'w',
          categoryId: null,
          note: '',
          frequency: f,
          startDate: DateTime(2026, 1, 1),
          endDate: null,
          nextOccurrence: DateTime(2026, 9, 1),
          lastGenerated: null,
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      }
      expect(FilteredAnalytics.monthlyRuleEstimate(mk('daily', 1000)), 30000);
      expect(FilteredAnalytics.monthlyRuleEstimate(mk('weekly', 7000)), 30000);
      expect(FilteredAnalytics.monthlyRuleEstimate(mk('monthly', 5000)), 5000);
      expect(FilteredAnalytics.monthlyRuleEstimate(mk('yearly', 12000)), 1000);
      expect(
        FilteredAnalytics.monthlyRuleEstimate(
          mk('monthly', 5000).copyWith(type: 'income'),
        ),
        0,
      );
      await db2.close();
    });
  });
}
