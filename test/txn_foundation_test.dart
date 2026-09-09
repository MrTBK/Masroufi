import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/templates_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

/// Phase-1 foundation: templates CRUD, exact restore (undo), multi-wallet
/// filter, amount-aware search. Pure repo level, in-memory DB.
void main() {
  AppDb mem() => AppDb.forTesting(NativeDatabase.memory());

  group('TemplatesRepo', () {
    late AppDb db;
    late TemplatesRepo templates;
    setUp(() {
      db = mem();
      templates = TemplatesRepo(db);
    });
    tearDown(() => db.close());

    test('create/list/rename/remove round-trip in order', () async {
      expect(await templates.all(), isEmpty);
      final a = await templates.create(
        name: 'Morning coffee',
        type: 'expense',
        amountMillimes: 5500,
        note: 'Café',
      );
      final b = await templates.create(
        name: 'Salary',
        type: 'income',
        amountMillimes: 2000000,
      );
      final list = await templates.all();
      expect([for (final t in list) t.id], [a, b]);
      expect(list.first.amountMillimes, 5500);
      await templates.rename(a, 'Coffee');
      expect((await templates.get(a))!.name, 'Coffee');
      await templates.remove(b);
      expect(await templates.all(), hasLength(1));
      expect(await templates.get(b), isNull);
    });

    test('validation rejects bad input, never writes', () async {
      for (final bad in [
        () => templates.create(name: '', type: 'expense', amountMillimes: 1),
        () => templates.create(name: 'x', type: 'loan', amountMillimes: 1),
        () => templates.create(name: 'x', type: 'expense', amountMillimes: 0),
        () => templates.create(
          name: 'x',
          type: 'transfer',
          amountMillimes: 100,
          walletId: 'w',
          toWalletId: 'w',
        ),
        () async => templates.rename('nope', ''),
      ]) {
        await expectLater(bad(), throwsArgumentError);
      }
      expect(await templates.all(), isEmpty);
    });

    test('transfer template requires two distinct wallets', () async {
      final id = await templates.create(
        name: 'To savings',
        type: 'transfer',
        amountMillimes: 100000,
        walletId: 'w1',
        toWalletId: 'w2',
      );
      final t = (await templates.get(id))!;
      expect(t.toWalletId, 'w2');
    });
  });

  group('restore (undo)', () {
    test('delete + restore returns the byte-identical row', () async {
      final db = mem();
      addTearDown(db.close);
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final cash = await wallets.create(name: 'Cash', initialMillimes: 100000);
      final id = await txns.addExpense(
        amountMillimes: 12500,
        walletId: cash,
        note: 'Café',
      );
      final before = (await txns.get(id))!;
      await txns.delete(id);
      expect(await txns.get(id), isNull);
      expect(
        await wallets.balance((await wallets.get(cash))!),
        100000,
      );
      await txns.restore(before);
      final after = (await txns.get(id))!;
      expect(after.id, before.id);
      expect(after.amountMillimes, 12500);
      expect(after.note, 'Café');
      expect(after.occurredAt, before.occurredAt);
      expect(after.createdAt, before.createdAt);
      expect(
        await wallets.balance((await wallets.get(cash))!),
        87500,
      );
      // Double restore (double undo) never duplicates.
      await txns.restore(before);
      expect(await txns.list(const TxnFilter(limit: 10)), hasLength(1));
    });
  });

  group('walletIds filter + amount search', () {
    test('walletIds matches either transfer endpoint', () async {
      final db = mem();
      addTearDown(db.close);
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final cash = await wallets.create(name: 'Cash');
      final bank = await wallets.create(name: 'Bank');
      await txns.addExpense(amountMillimes: 1000, walletId: cash);
      await txns.addTransfer(
        amountMillimes: 5000,
        fromWalletId: cash,
        toWalletId: bank,
      );
      final onlyBank = await txns.list(TxnFilter(walletIds: [bank], limit: 10));
      expect(onlyBank, hasLength(1));
      expect(onlyBank.single.type, 'transfer');
      final both = await txns.list(
        TxnFilter(walletIds: [cash, bank], limit: 10),
      );
      expect(both, hasLength(2));
    });

    test('numeric search matches exact amounts, text still note-only',
        () async {
      final db = mem();
      addTearDown(db.close);
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final cash = await wallets.create(name: 'Cash');
      await txns.addExpense(
        amountMillimes: 12500,
        walletId: cash,
        note: 'Café',
      );
      await txns.addExpense(
        amountMillimes: 8000,
        walletId: cash,
        note: 'Taxi',
      );
      final byAmount = await txns.list(
        const TxnFilter(search: '12.5', limit: 10),
      );
      expect(byAmount, hasLength(1));
      expect(byAmount.single.note, 'Café');
      final byNote = await txns.list(
        const TxnFilter(search: 'taxi', limit: 10),
      );
      expect(byNote, hasLength(1));
    });
  });
}
