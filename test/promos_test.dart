import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/promos/promos.dart';

Promo _p(String id, DateTime start, DateTime end) => Promo(
  id: id,
  titleKey: 't',
  bodyKey: 'b',
  link: 'https://example.com/$id',
  start: start,
  end: end,
);

void main() {
  final day = DateTime(2026, 9, 13);
  final wide = _p('a', DateTime(2026, 1, 1), DateTime(2026, 12, 31));

  group('Promos.activeOn', () {
    test('empty pool means house invite path', () {
      expect(Promos.activeOn(day, pool: const []), isEmpty);
      expect(Promos.activeOn(day), isEmpty);
    });

    test('keeps live promos, drops expired and future', () {
      final pool = [
        wide,
        _p('old', DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
        _p('next', DateTime(2026, 10, 1), DateTime(2026, 12, 31)),
      ];
      final active = Promos.activeOn(day, pool: pool);
      expect(active.map((p) => p.id), ['a']);
    });

    test('start and end days are inclusive', () {
      final pool = [_p('edge', day, day)];
      expect(Promos.activeOn(day, pool: pool).map((p) => p.id), ['edge']);
    });
  });

  group('Promos.pickFor', () {
    test('null when nothing active', () {
      expect(Promos.pickFor(day, pool: const []), isNull);
    });

    test('deterministic per day, rotates across days', () {
      final pool = [
        wide,
        _p('b', DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
      ];
      final first = Promos.pickFor(day, pool: pool)!;
      expect(Promos.pickFor(day, pool: pool)!.id, first.id);
      final second = Promos.pickFor(
        day.add(const Duration(days: 1)),
        pool: pool,
      )!;
      expect(second.id, isNot(first.id));
    });
  });
}
