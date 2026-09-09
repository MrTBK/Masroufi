import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/money/recurring.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/recurring_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

void main() {
  group('Recurring.nextAfter', () {
    test('daily/weekly', () {
      expect(
        Recurring.nextAfter(DateTime(2026, 9, 6), 'daily'),
        DateTime(2026, 9, 7),
      );
      expect(
        Recurring.nextAfter(DateTime(2026, 9, 6), 'weekly'),
        DateTime(2026, 9, 13),
      );
    });
    test('monthly clamps month-end (Jan 31 -> Feb 28)', () {
      expect(
        Recurring.nextAfter(DateTime(2026, 1, 31), 'monthly'),
        DateTime(2026, 2, 28),
      );
    });
    test('monthly leap year (Jan 31 2024 -> Feb 29)', () {
      expect(
        Recurring.nextAfter(DateTime(2024, 1, 31), 'monthly'),
        DateTime(2024, 2, 29),
      );
    });
    test('yearly Feb 29 -> Feb 28 non-leap', () {
      expect(
        Recurring.nextAfter(DateTime(2024, 2, 29), 'yearly'),
        DateTime(2025, 2, 28),
      );
    });
    test('monthly Dec -> Jan next year', () {
      expect(
        Recurring.nextAfter(DateTime(2026, 12, 15), 'monthly'),
        DateTime(2027, 1, 15),
      );
    });
  });

  group('occurrencesBetween', () {
    test('weekly salary 4x in September', () {
      final dates = Recurring.occurrencesBetween(
        start: DateTime(2026, 9, 1),
        frequency: 'weekly',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(dates.map((d) => d.day), [1, 8, 15, 22, 29]);
    });
    test('respects end date', () {
      final dates = Recurring.occurrencesBetween(
        start: DateTime(2026, 9, 1),
        frequency: 'monthly',
        from: DateTime(2026, 9, 1),
        to: DateTime(2027, 9, 1),
        end: DateTime(2026, 11, 15),
      );
      expect(dates.length, 3); // Sep, Oct, Nov
    });
  });

  group('RecurringRepo.generateDue', () {
    late AppDb db;
    late RecurringRepo rules;
    late TransactionsRepo txns;
    late WalletsRepo wallets;

    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      rules = RecurringRepo(db);
      txns = TransactionsRepo(db);
      wallets = WalletsRepo(db);
    });
    tearDown(() => db.close());

    test('generates due, never duplicates on rerun', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 0);
      await rules.create(
        type: 'income',
        amountMillimes: 2500000,
        walletId: cash,
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 25),
      );
      final first = await rules.generateDue(now: DateTime(2026, 3, 26, 12));
      expect(first.length, 3); // Jan 25, Feb 25, Mar 25
      final second = await rules.generateDue(now: DateTime(2026, 3, 26, 12));
      expect(second, isEmpty); // rerun creates nothing
      final all = await txns.list(const TxnFilter(limit: 50));
      expect(all.length, 3);
      expect(all.every((t) => t.recurringRuleId != null), isTrue);
      final w = await wallets.get(cash);
      expect(await wallets.balance(w!), 7500000);
    });

    test('stops at end date + skip advances', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 0);
      final id = await rules.create(
        type: 'expense',
        amountMillimes: 45000,
        walletId: cash,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 15),
      );
      await rules.skipOccurrence(id); // skip Sep 1
      final made = await rules.generateDue(now: DateTime(2026, 12, 1));
      expect(made.length, 1); // only Oct 1 (Nov past end date)
    });

    test('disabled rule generates nothing', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 0);
      final id = await rules.create(
        type: 'expense',
        amountMillimes: 1000,
        walletId: cash,
        frequency: 'daily',
        startDate: DateTime(2026, 1, 1),
      );
      await rules.updateRule(id, isActive: false);
      expect(await rules.generateDue(now: DateTime(2026, 6, 1)), isEmpty);
    });
  });
}
