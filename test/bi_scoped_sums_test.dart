import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('scoped sums (BI filter bar)', () {
    late AppDb db;
    late AnalyticsRepo analytics;
    late TransactionsRepo txns;
    final sept = (
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 10, 1),
    );

    setUp(() async {
      db = _db();
      analytics = AnalyticsRepo(db);
      txns = TransactionsRepo(db);
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'cash', name: 'Cash'));
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'bank', name: 'Bank'));
      await txns.addExpense(
        amountMillimes: 100000,
        walletId: 'cash',
        categoryId: 'food',
        when: DateTime(2026, 9, 5),
      );
      await txns.addExpense(
        amountMillimes: 200000,
        walletId: 'bank',
        categoryId: 'taxi',
        when: DateTime(2026, 9, 6),
      );
      await txns.addIncome(
        amountMillimes: 500000,
        walletId: 'bank',
        when: DateTime(2026, 9, 7),
      );
      await txns.addTransfer(
        amountMillimes: 50000,
        fromWalletId: 'cash',
        toWalletId: 'bank',
        when: DateTime(2026, 9, 8),
      );
    });

    tearDown(() => db.close());

    test('empty wallet list matches all; transfers excluded', () async {
      expect(
        await analytics.expenseTotalW([], sept.start, sept.end),
        300000,
      );
      expect(
        await analytics.incomeTotalW([], sept.start, sept.end),
        500000,
      );
    });

    test('single wallet scopes both legs of a transfer', () async {
      expect(
        await analytics.expenseTotalW(['cash'], sept.start, sept.end),
        100000,
      );
      final cashOnly = await analytics.txnCount(
        walletIds: ['cash'],
        from: sept.start,
        to: sept.end,
      );
      // cash expense + cash->bank transfer.
      expect(cashOnly, 2);
    });

    test('txnCount honors type, category, and range', () async {
      expect(
        await analytics.txnCount(
          type: 'expense',
          from: sept.start,
          to: sept.end,
        ),
        2,
      );
      expect(
        await analytics.txnCount(
          categoryIds: ['food'],
          from: sept.start,
          to: sept.end,
        ),
        1,
      );
      expect(await analytics.txnCount(), 4);
    });

    test('byCategory accepts a wallet filter', () async {
      final byCat = await analytics.expenseByCategory(
        sept.start,
        sept.end,
        walletIds: ['bank'],
      );
      expect(byCat, {'taxi': 200000});
    });

    test('sameMonthLastYear anchors YoY', () async {
      final yoy = await analytics.sameMonthLastYear(2026, 9);
      expect(yoy.expense, 0);
      await txns.addExpense(
        amountMillimes: 150000,
        walletId: 'cash',
        when: DateTime(2025, 9, 10),
      );
      final yoy2 = await analytics.sameMonthLastYear(2026, 9);
      expect(yoy2.expense, 150000);
    });
  });
}
