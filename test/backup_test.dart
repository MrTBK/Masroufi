import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/features/backup/backup_codec.dart';

void main() {
  Map<String, dynamic> sample() => BackupCodec.build({
    'wallets': [
      {'id': 'w1', 'name': 'Cash'},
    ],
    'categories': [
      {'id': 'c1'},
    ],
    'transactions': [
      {'id': 't1', 'note': 'مقهى'},
    ],
    'budgets': [],
    'settings': [
      {'key': 'language', 'value': 'ar'},
    ],
  });

  group('BackupCodec', () {
    test('round-trip validates', () {
      final raw = BackupCodec.encode(sample());
      expect(BackupCodec.tryDecode(raw), isNotNull);
    });

    test('rejects wrong version', () {
      final bad = sample()..['version'] = 999;
      expect(BackupCodec.tryDecode(BackupCodec.encode(bad)), isNull);
    });

    test('v8 round-trip includes v2+v3+v4 tables', () {
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(sample()))!;
      expect(decoded['version'], 8);
      for (final k in [
        'recurring_rules',
        'category_budgets',
        'savings_goals',
        'savings_contributions',
        'debts',
        'debt_payments',
        'txn_templates',
        'txn_splits',
      ]) {
        expect(decoded[k], isList);
      }
    });

    test('old v6 backup upgrades to v8 with empty templates', () {
      final v6 = {
        'version': 6,
        'exportedAt': '2026-01-01T00:00:00',
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
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v6))!;
      expect(decoded['version'], 8);
      expect(decoded['txn_templates'], isEmpty);
      expect(decoded['txn_splits'], isEmpty);
    });

    test('old v1 backup restores with empty v2 tables', () {
      final v1 = {
        'version': 1,
        'exportedAt': '2026-01-01T00:00:00',
        'wallets': [],
        'categories': [],
        'transactions': [],
        'budgets': [],
        'settings': [],
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v1))!;
      expect(decoded['version'], 8);
      expect(decoded['debts'], isEmpty);
      expect(decoded['recurring_rules'], isEmpty);
    });

    test('old v4 backup upgrades to v8', () {
      final v4 = {
        'version': 4,
        'exportedAt': '2026-01-01T00:00:00',
        'wallets': [],
        'categories': [
          {'id': 'c1', 'nameKey': 'cat_cafe'},
        ],
        'transactions': [],
        'budgets': [],
        'settings': [],
        'recurring_rules': [],
        'category_budgets': [],
        'savings_goals': [],
        'savings_contributions': [],
        'debts': [],
        'debt_payments': [],
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v4))!;
      expect(decoded['version'], 8);
      // v4 rows carry no parentId: restore treats them as top-level.
      final cats = decoded['categories'] as List;
      expect((cats.single as Map)['parentId'], isNull);
    });

    test('old v3 backup upgrades to v8', () {
      final v3 = {
        'version': 3,
        'exportedAt': '2026-01-01T00:00:00',
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
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v3))!;
      expect(decoded['version'], 8);
      expect(decoded['wallets'], isEmpty);
    });

    test('old v2 backup upgrades to v8', () {
      final v2 = {
        'version': 2,
        'exportedAt': '2026-01-01T00:00:00',
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
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v2))!;
      expect(decoded['version'], 8);
      expect(decoded['wallets'], isEmpty);
    });

    test('rejects missing table', () {
      final bad = sample()..remove('wallets');
      expect(BackupCodec.tryDecode(BackupCodec.encode(bad)), isNull);
    });

    test('rejects corrupt input', () {
      expect(BackupCodec.tryDecode('not json{{{'), isNull);
      expect(BackupCodec.tryDecode('[]'), isNull);
    });

    test('old v5 backup upgrades to v8 with wallet style defaults', () {
      final v5 = {
        'version': 5,
        'exportedAt': '2026-01-01T00:00:00',
        'wallets': [
          {'id': 'w1', 'name': 'Cash'},
        ],
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
      };
      final decoded = BackupCodec.tryDecode(BackupCodec.encode(v5))!;
      expect(decoded['version'], 8);
      // Per-row wallet styling defaults on restore (backup_page).
      final wallets = decoded['wallets'] as List;
      expect((wallets.single as Map)['colorKey'], isNull);
    });

    test('CSV keeps Arabic readable + correct columns', () {
      final csv = BackupCodec.buildCsv([
        {
          'date': '2026-09-06',
          'type': 'expense',
          'amount_millimes': 12500,
          'amount_tnd': '12.500',
          'category': 'مقهى',
          'wallet': 'Cash',
          'to_wallet': '',
          'note': 'قهوة',
        },
      ]);
      expect(csv, contains('date,type,amount_millimes'));
      expect(csv, contains('مقهى'));
      expect(csv, contains('12500'));
    });

    test('CSV import parses our own export (incl. BOM + Arabic)', () {
      const csv =
          '\uFEFFdate,type,amount_millimes,amount_tnd,category,wallet,to_wallet,note\n'
          '2026-09-06,expense,12500,12.500,مقهى,Cash,,قهوة\n'
          '2026-09-07,income,,500,Ratib?,Cash,,';
      final preview = BackupCodec.parseCsvImport(csv);
      expect(preview.errors, isEmpty);
      expect(preview.rows, hasLength(2));
      expect(preview.rows[0].amountMillimes, 12500);
      expect(preview.rows[0].categoryName, 'مقهى');
      expect(preview.rows[0].note, 'قهوة');
      expect(preview.rows[1].type, 'income');
      expect(preview.rows[1].amountMillimes, 500000);
    });

    test('CSV import defaults type, parses dd/MM/yyyy + TND text', () {
      const csv =
          'date,amount_tnd,wallet,note\n06/09/2026,"12,500",Cash,taxi\n';
      final preview = BackupCodec.parseCsvImport(csv);
      expect(preview.errors, isEmpty);
      expect(preview.rows.single.type, 'expense');
      expect(preview.rows.single.amountMillimes, 12500);
      expect(
        preview.rows.single.occurredAt,
        DateTime(2026, 9, 6),
      );
    });

    test('CSV import collects per-row errors, keeps valid rows', () {
      const csv =
          'date,type,amount_millimes,wallet,to_wallet,note\n'
          'not-a-date,expense,1000,Cash,,ok-date-bad\n'
          '2026-09-06,lottery,1000,Cash,,ok-type-bad\n'
          '2026-09-06,expense,-5,Cash,,ok-amount-bad\n'
          '2026-09-06,expense,1000,,,ok-wallet-missing\n'
          '2026-09-06,transfer,1000,Cash,,ok-towallet-missing\n'
          '2026-09-06,expense,0,Cash,,ok-zero\n'
          '2026-09-06,expense,2500,Cash,,fine\n';
      final preview = BackupCodec.parseCsvImport(csv);
      expect(preview.rows, hasLength(1));
      expect(preview.rows.single.amountMillimes, 2500);
      expect(preview.errors, hasLength(6));
      expect(preview.errors[0].row, 2);
      expect(preview.errors[0].message, contains('bad-date'));
      expect(preview.errors[1].message, contains('bad-type'));
      expect(preview.errors[2].message, contains('bad-amount'));
      expect(preview.errors[3].message, 'missing-wallet');
      expect(preview.errors[4].message, 'missing-to-wallet');
    });

    test('CSV import rejects missing columns + empty input', () {
      const noAmount = 'date,wallet\n2026-09-06,Cash\n';
      final p1 = BackupCodec.parseCsvImport(noAmount);
      expect(p1.rows, isEmpty);
      expect(p1.errors.single.message, 'missing-columns');
      final p2 = BackupCodec.parseCsvImport('\n  \n');
      expect(p2.rows, isEmpty);
      expect(p2.errors.single.message, 'empty');
    });
  });
}
