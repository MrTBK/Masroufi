import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/wealth/net_worth.dart';
import 'package:masroufi/core/widget/masroufi_widget.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/features/reports/year_review_card.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('NetWorth pure', () {
    test('buildTrend sorts oldest-first, delta pct int-only', () {
      final t = NetWorth.buildTrend([
        (year: 2026, month: 9, worth: 1100),
        (year: 2026, month: 7, worth: 1000),
        (year: 2026, month: 8, worth: 1050),
      ]);
      expect(t.map((p) => p.month).toList(), [7, 8, 9]);
      final d = NetWorth.delta(t)!;
      expect(d.diff, 50);
      // 50/1050 ≈ 5%.
      expect(d.pct, 5);
      expect(NetWorth.delta(t.sublist(0, 1)), isNull);
    });

    test('formula: visible initials + flows + savings', () async {
      final db = _db();
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'w1', name: 'Cash'));
      await db
          .into(db.wallets)
          .insert(
            WalletsCompanion.insert(
              id: 'w1h',
              name: 'Hidden',
              initialMillimes: const drift.Value(999999),
            ),
          );
      // Hide second wallet: must not leak into net worth.
      await (db.update(
        db.wallets,
      )..where((w) => w.id.equals('w1h'))).write(
        const WalletsCompanion(isBalanceHidden: drift.Value(true)),
      );
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 't1',
              type: 'income',
              amountMillimes: 10000,
              walletId: 'w1',
              occurredAt: DateTime(2026, 8, 15),
            ),
          );
      final trend = await NetWorth.trend(
        db: db,
        now: DateTime(2026, 9, 9),
        monthsBack: 2,
      );
      expect(trend.length, 2);
      // Aug end: 0 + 10000 = 10000 (hidden 999999 excluded).
      expect(trend.first.worth, 10000);
      expect(trend.last.worth, 10000);
      await db.close();
    });
  });

  group('YearReviewData builder', () {
    test('picks top category, net math', () {
      final d = YearReviewData.build(
        year: 2026,
        incomeMillimes: 1200000,
        expenseMillimes: 800000,
        txnCount: 42,
        byCategory: const {'a': 500000, 'b': 300000},
        names: const {'a': 'Food', 'b': 'Taxi'},
      );
      expect(d.netMillimes, 400000);
      expect(d.topCategory, 'Food');
      expect(d.topCategoryMillimes, 500000);
    });
  });

  group('savings widget variant builder', () {
    test('formats current/target with isolates', () {
      final l = savingsWidgetLines(
        goalName: 'Trip',
        currentMillimes: 50000,
        targetMillimes: 100000,
        lang: 'en',
      );
      expect(l.title, 'Trip');
      expect(l.balance.contains('50.000'), isTrue);
      expect(l.balance.contains('100.000'), isTrue);
    });
  });
}
