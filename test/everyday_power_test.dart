import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/fx/fx.dart';
import 'package:masroufi/core/security/hidden_gate.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/splits_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/features/backup/backup_codec.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('splits invariant', () {
    test('sum must equal parent, parent untouched', () async {
      final db = _db();
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'w1', name: 'Cash'));
      final txns = TransactionsRepo(db);
      final splits = SplitsRepo(db);
      final id = await txns.addExpense(
        amountMillimes: 10000,
        walletId: 'w1',
      );
      // Valid split.
      await splits.setSplits(id, [
        (categoryId: null, amountMillimes: 6000, note: ''),
        (categoryId: null, amountMillimes: 4000, note: ''),
      ]);
      expect(await splits.totalFor(id), 10000);
      // Parent untouched.
      expect((await txns.get(id))!.amountMillimes, 10000);
      // Mismatch throws, writes nothing (still 10000).
      expect(
        () => splits.setSplits(id, [
          (categoryId: null, amountMillimes: 5000, note: ''),
        ]),
        throwsStateError,
      );
      expect(await splits.totalFor(id), 10000);
      // Zero/empty throws.
      expect(() => splits.setSplits(id, []), throwsStateError);
      await db.close();
    });
  });

  group('Fx currency math (int-only)', () {
    test('toTnd: cents * rate ~/ 100', () {
      // 12.50 EUR at 3400 millimes/EUR → 12.50*3400 = 42500.
      expect(
        Fx.toTndMillimes(
          origMinor: 1250,
          currency: 'EUR',
          rateMillimesPerUnit: 3400,
        ),
        42500,
      );
      expect(
        () => Fx.toTndMillimes(
          origMinor: 100,
          currency: 'XYZ',
          rateMillimesPerUnit: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('formatOriginal 2 decimals + stale badge rule', () {
      expect(Fx.formatOriginal(1250, 'eur'), '12.50 EUR');
      final now = DateTime(2026, 9, 9);
      expect(
        Fx.isStale(
          updatedAt: now.subtract(const Duration(days: 31)),
          now: now,
        ),
        isTrue,
      );
      expect(
        Fx.isStale(
          updatedAt: now.subtract(const Duration(days: 5)),
          now: now,
        ),
        isFalse,
      );
      expect(Fx.isStale(updatedAt: null, now: now), isTrue);
      expect(Fx.parseMinor('12.50'), 1250);
      expect(Fx.parseMinor('12,5'), 1250);
    });
  });

  group('HiddenGate paths', () {
    test('needsAuth only when revealing + PIN exists', () {
      expect(
        HiddenGate.needsAuth(revealsHidden: false, hasPin: true),
        isFalse,
      );
      expect(
        HiddenGate.needsAuth(revealsHidden: true, hasPin: false),
        isFalse,
      );
      expect(
        HiddenGate.needsAuth(revealsHidden: true, hasPin: true),
        isTrue,
      );
    });
  });

  group('backup codec v8', () {
    test('v7 decodes to v8 with empty splits + null originals', () {
      final v7 = BackupCodec.encode(
        BackupCodec.build({
          'wallets': [],
          'categories': [],
          'transactions': [],
          'budgets': [],
          'settings': [],
          'recurring_rules': [],
          'category_budgets': [],
          'savings_goals': [],
          'savings_contributions': [],
          'debts': [],
          'debt_payments': [],
          'txn_templates': [],
        }),
      );
      // Downgrade the version stamp to 7 to simulate an old backup.
      final raw7 = v7.replaceFirst('"version":8', '"version":7');
      final decoded = BackupCodec.tryDecode(raw7);
      expect(decoded, isNotNull);
      expect(decoded!['version'], 8);
      expect(decoded['txn_splits'], isEmpty);
    });

    test('v8 round-trips splits + originals', () {
      final built = BackupCodec.build({
        'wallets': [],
        'categories': [],
        'transactions': [
          {
            'id': 't1',
            'type': 'expense',
            'amountMillimes': 42500,
            'walletId': 'w1',
            'toWalletId': null,
            'categoryId': null,
            'recurringRuleId': null,
            'origMinor': 1250,
            'origCurrency': 'EUR',
            'occurredAt': DateTime(2026, 9, 9).toIso8601String(),
            'note': '',
            'createdAt': DateTime(2026, 9, 9).toIso8601String(),
            'updatedAt': DateTime(2026, 9, 9).toIso8601String(),
          },
        ],
        'budgets': [],
        'settings': [],
        'recurring_rules': [],
        'category_budgets': [],
        'savings_goals': [],
        'savings_contributions': [],
        'debts': [],
        'debt_payments': [],
        'txn_templates': [],
        'txn_splits': [
          {
            'id': 's1',
            'txnId': 't1',
            'categoryId': null,
            'amountMillimes': 42500,
            'note': '',
            'createdAt': DateTime(2026, 9, 9).toIso8601String(),
          },
        ],
      });
      expect(BackupCodec.validate(built), isNull);
      final back = BackupCodec.tryDecode(BackupCodec.encode(built))!;
      expect((back['txn_splits'] as List).length, 1);
      expect(
        (back['transactions'] as List).first['origCurrency'],
        'EUR',
      );
    });
  });

  group('migration v1->v8 shapes', () {
    test('fresh v8 has splits table + orig columns', () async {
      final db = _db();
      // Splits usable on a fresh v8 database.
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'w1', name: 'Cash'));
      final txns = TransactionsRepo(db);
      final id = await txns.addExpense(
        amountMillimes: 2000,
        walletId: 'w1',
        origMinor: 100,
        origCurrency: 'USD',
      );
      final t = (await txns.get(id))!;
      expect(t.origMinor, 100);
      expect(t.origCurrency, 'USD');
      await SplitsRepo(db).setSplits(id, [
        (categoryId: null, amountMillimes: 2000, note: ''),
      ]);
      await db.close();
    });
  });
}
