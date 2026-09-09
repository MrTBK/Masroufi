import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/backup/auto_backup.dart';
import 'package:masroufi/core/safety/data_health.dart';
import 'package:masroufi/core/safety/duplicate_guard.dart';
import 'package:masroufi/data/database/app_db.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('AutoBackup', () {
    test('shouldRun weekly', () {
      final now = DateTime(2026, 9, 9);
      expect(AutoBackup.shouldRun(lastRun: null, now: now), isTrue);
      expect(
        AutoBackup.shouldRun(
          lastRun: now.subtract(const Duration(days: 6)),
          now: now,
        ),
        isFalse,
      );
      expect(
        AutoBackup.shouldRun(
          lastRun: now.subtract(const Duration(days: 7)),
          now: now,
        ),
        isTrue,
      );
    });

    test('prune keeps last 4', () {
      final files = [
        for (var i = 0; i < 6; i++) '/d/masroufi_auto_${1000 + i}.json',
      ];
      final dead = AutoBackup.prune(files);
      expect(dead.length, 2);
      expect(dead.first.contains('1000'), isTrue);
      expect(AutoBackup.prune(files.sublist(0, 4)), isEmpty);
    });

    test('shouldNag 14+ days dismissible', () {
      final now = DateTime(2026, 9, 9);
      expect(
        AutoBackup.shouldNag(lastBackup: null, dismissedAt: null, now: now),
        isTrue,
      );
      expect(
        AutoBackup.shouldNag(
          lastBackup: now.subtract(const Duration(days: 13)),
          dismissedAt: null,
          now: now,
        ),
        isFalse,
      );
      final old = now.subtract(const Duration(days: 20));
      expect(
        AutoBackup.shouldNag(
          lastBackup: old,
          dismissedAt: null,
          now: now,
        ),
        isTrue,
      );
      expect(
        AutoBackup.shouldNag(
          lastBackup: old,
          dismissedAt: now.subtract(const Duration(days: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('DuplicateGuard', () {
    test('inWindow 30min', () {
      final now = DateTime(2026, 9, 9, 12);
      expect(
        DuplicateGuard.inWindow(now.subtract(const Duration(minutes: 29)), now),
        isTrue,
      );
      expect(
        DuplicateGuard.inWindow(now.subtract(const Duration(minutes: 31)), now),
        isFalse,
      );
      expect(
        DuplicateGuard.inWindow(now.add(const Duration(minutes: 1)), now),
        isFalse,
      );
    });

    test('findRecent same wallet+cat+amount', () async {
      final db = _db();
      final wallets = db.wallets;
      final txns = db.transactions;
      const wid = 'w1';
      await db
          .into(wallets)
          .insert(
            WalletsCompanion.insert(id: wid, name: 'Cash'),
          );
      final now = DateTime.now();
      await db
          .into(txns)
          .insert(
            TransactionsCompanion.insert(
              id: 't1',
              type: 'expense',
              amountMillimes: 5000,
              walletId: wid,
              categoryId: const drift.Value('c1'),
              occurredAt: now.subtract(const Duration(minutes: 10)),
            ),
          );
      final hit = await DuplicateGuard.findRecent(
        db: db,
        type: 'expense',
        amountMillimes: 5000,
        walletId: wid,
        categoryId: 'c1',
        now: now,
      );
      expect(hit?.id, 't1');
      // Different amount → no hit.
      final miss = await DuplicateGuard.findRecent(
        db: db,
        type: 'expense',
        amountMillimes: 6000,
        walletId: wid,
        categoryId: 'c1',
        now: now,
      );
      expect(miss, isNull);
      // Transfers never warn.
      expect(
        await DuplicateGuard.findRecent(
          db: db,
          type: 'transfer',
          amountMillimes: 5000,
          walletId: wid,
          categoryId: null,
          now: now,
        ),
        isNull,
      );
      await db.close();
    });
  });

  group('DataHealth', () {
    test('scan finds dangling refs, repair nulls categories, never deletes',
        () async {
      final db = _db();
      await db
          .into(db.wallets)
          .insert(WalletsCompanion.insert(id: 'w1', name: 'Cash'));
      await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(id: 'c1'));
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 't1',
              type: 'expense',
              amountMillimes: 1000,
              walletId: 'w1',
              categoryId: const drift.Value('missing-cat'),
              occurredAt: DateTime.now(),
            ),
          );
      var issues = await DataHealth.scan(db);
      expect(
        issues.any(
          (e) => e.table == 'transactions' && e.field == 'categoryId',
        ),
        isTrue,
      );
      final n = await DataHealth.repair(db);
      expect(n >= 1, isTrue);
      // Row still exists, category nulled.
      final t = await (db.select(
        db.transactions,
      )..where((x) => x.id.equals('t1'))).getSingle();
      expect(t.categoryId, isNull);
      issues = await DataHealth.scan(db);
      expect(
        issues.any(
          (e) => e.table == 'transactions' && e.field == 'categoryId',
        ),
        isFalse,
      );
      await db.close();
    });
  });
}
