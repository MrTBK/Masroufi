import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/money/money.dart';

void main() {
  group('Money.parse', () {
    test('dot decimal (TN format)', () => expect(Money.parse('12.500'), 12500));
    test(
      'comma decimal (FR format)',
      () => expect(Money.parse('12,500'), 12500),
    );
    test('plain units', () => expect(Money.parse('100'), 100000));
    test('thousands + decimal', () {
      expect(Money.parse('1,250.500'), 1250500);
      expect(Money.parse('1 250.500'), 1250500);
    });
    test('rounding beyond millimes', () {
      expect(Money.parse('1.2349'), 1235);
      expect(Money.parse('1.2344'), 1234);
    });
    test('MVP scenario values', () {
      expect(Money.parse('12.500'), 12500);
      expect(Money.parse('8'), 8000);
      expect(Money.parse('500'), 500000);
      expect(Money.parse('100'), 100000);
    });
    test('rejects invalid', () {
      expect(() => Money.parse(''), throwsFormatException);
      expect(() => Money.parse('abc'), throwsFormatException);
      expect(() => Money.parse('0'), throwsFormatException);
      expect(() => Money.parse('0.000'), throwsFormatException);
    });
  });

  group('Money precision (no float)', () {
    test('0.1 + 0.2 == 0.3 exactly', () {
      expect(Money.parse('0.1') + Money.parse('0.2'), Money.parse('0.3'));
    });
    test('MVP balance chain in integers', () {
      var balance = Money.parse('100'); // 100.000
      balance -= Money.parse('12.500'); // 87.500
      expect(balance, 87500);
      balance -= Money.parse('8'); // 79.500
      expect(balance, 79500);
      balance += Money.parse('500'); // 579.500
      expect(balance, 579500);
    });
  });

  group('Money.format', () {
    test('english', () => expect(Money.format(12500), '12.500 TND'));
    test(
      'arabic suffix',
      () => expect(Money.format(12500, lang: 'ar').endsWith('د.ت'), isTrue),
    );
    test(
      'thousands grouping',
      () => expect(Money.format(1250500), '1,250.500 TND'),
    );
    test('negative', () => expect(Money.format(-87500), '-87.500 TND'));
    test('zero', () => expect(Money.format(0), '0.000 TND'));
  });
}
