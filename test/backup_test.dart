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

    test('rejects missing table', () {
      final bad = sample()..remove('wallets');
      expect(BackupCodec.tryDecode(BackupCodec.encode(bad)), isNull);
    });

    test('rejects corrupt input', () {
      expect(BackupCodec.tryDecode('not json{{{'), isNull);
      expect(BackupCodec.tryDecode('[]'), isNull);
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
  });
}
