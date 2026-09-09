import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/money/money.dart';
import 'package:masroufi/core/widgets/design.dart';

/// RTL money regression net (brief §6-7, §26, §33): the screenshot bug
/// rendered `-4,420.500 د.ت` with the minus detached on the wrong side.
/// Contract:
/// - `Money.format` stays raw ASCII (storage/CSV/tests; never isolates).
/// - `Money.inline` embeds isolate-wrapped runs for Arabic sentences.
/// - `MoneyText` forces an LTR run so the sign can never migrate.
void main() {
  const cases = [5000, -5000, 0, 2500000, -4420500];

  group('Money.format raw contract', () {
    test('positive/negative/zero across locales', () {
      expect(Money.format(5000), '5.000 TND');
      expect(Money.format(-5000), '-5.000 TND');
      expect(Money.format(0), '0.000 TND');
      expect(Money.format(2500000), '2,500.000 TND');
      expect(Money.format(-4420500), '-4,420.500 TND');
      expect(Money.format(-4420500, lang: 'ar'), '-4,420.500 د.ت');
      expect(Money.format(2500000, lang: 'ar'), '2,500.000 د.ت');
      expect(Money.format(0, lang: 'ar'), '0.000 د.ت');
      expect(Money.format(-5000, lang: 'fr'), '-5.000 TND');
    });

    test('never emits bidi controls (CSV/storage safe)', () {
      for (final v in cases) {
        for (final lang in ['en', 'fr', 'ar']) {
          final s = Money.format(v, lang: lang);
          expect(s.contains('\u2066'), isFalse, reason: '$v/$lang');
          expect(s.contains('\u2069'), isFalse, reason: '$v/$lang');
          expect(s.contains('\u200E'), isFalse, reason: '$v/$lang');
          expect(s.contains('\u200F'), isFalse, reason: '$v/$lang');
        }
      }
    });

    test('int millimes only: no double artifacts', () {
      // 0.1 + 0.2 style hazards must be impossible: every formatted
      // fraction is exactly 3 digits from integer math.
      for (final v in cases) {
        final frac = Money.format(v).split(' ').first.split('.').last;
        expect(frac, hasLength(3));
        expect(int.tryParse(frac), isNotNull);
      }
    });
  });

  group('Money.inline isolates', () {
    test('stripped isolates equal raw format', () {
      for (final v in cases) {
        for (final lang in ['en', 'fr', 'ar']) {
          final s = Money.inline(v, lang: lang);
          expect(s.startsWith('\u2066'), isTrue, reason: '$v/$lang');
          expect(s.endsWith('\u2069'), isTrue, reason: '$v/$lang');
          expect(
            s.replaceAll('\u2066', '').replaceAll('\u2069', ''),
            Money.format(v, lang: lang),
          );
        }
      }
    });
  });

  group('MoneyText LTR-stable runs', () {
    Future<void> pumpAmount(
      WidgetTester t, {
      required int millimes,
      required String lang,
      required String type,
      TextStyle? style,
    }) async {
      // Hostile host: deep RTL paragraph, dark surface — the run must
      // still render sign-attached on its own LTR island.
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: MoneyText(
                millimes: millimes,
                lang: lang,
                type: type,
                style: style,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    TextDirection nearestDirection(WidgetTester t, Finder text) {
      // visitAncestorElements walks nearest-first, so .first is the
      // MoneyText-owned LTR island (not the RTL host above it).
      final dirs = find.ancestor(
        of: text,
        matching: find.byType(Directionality),
      );
      expect(dirs.evaluate(), isNotEmpty);
      return t.widgetList<Directionality>(dirs).first.textDirection;
    }

    testWidgets('negative Arabic neutral: sign attached, LTR island', (
      t,
    ) async {
      await pumpAmount(t, millimes: -4420500, lang: 'ar', type: 'neutral');
      final finder = find.text('-4,420.500 د.ت');
      expect(finder, findsOneWidget);
      expect(nearestDirection(t, finder), TextDirection.ltr);
    });

    testWidgets('positive/zero Arabic neutral', (t) async {
      await pumpAmount(t, millimes: 2500000, lang: 'ar', type: 'neutral');
      expect(find.text('2,500.000 د.ت'), findsOneWidget);
      await pumpAmount(t, millimes: 0, lang: 'ar', type: 'neutral');
      expect(find.text('0.000 د.ت'), findsOneWidget);
    });

    testWidgets('typed glyphs survive in RTL', (t) async {
      await pumpAmount(t, millimes: 5500, lang: 'ar', type: 'expense');
      expect(find.text('− 5.500 د.ت'), findsOneWidget);
      await pumpAmount(t, millimes: 2500000, lang: 'ar', type: 'income');
      expect(find.text('+ 2,500.000 د.ت'), findsOneWidget);
      await pumpAmount(t, millimes: 100000, lang: 'ar', type: 'transfer');
      expect(find.text('⇄ 100.000 د.ت'), findsOneWidget);
    });

    testWidgets('typed modes take abs (no double signs)', (t) async {
      await pumpAmount(t, millimes: -5500, lang: 'en', type: 'expense');
      expect(find.text('− 5.500 TND'), findsOneWidget);
      expect(find.textContaining('--'), findsNothing);
    });

    testWidgets('neutral inherits caller style untouched', (t) async {
      const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 30);
      await pumpAmount(
        t,
        millimes: 123456,
        lang: 'en',
        type: 'neutral',
        style: style,
      );
      final text = t.widget<Text>(find.text('123.456 TND'));
      expect(text.style?.fontWeight, FontWeight.bold);
      expect(text.style?.fontSize, 30);
      // No forced semantic color on neutral.
      expect(text.style?.color, isNull);
    });

    testWidgets('french keeps TND suffix, LTR island', (t) async {
      await pumpAmount(t, millimes: -5000, lang: 'fr', type: 'neutral');
      final finder = find.text('-5.000 TND');
      expect(finder, findsOneWidget);
      expect(nearestDirection(t, finder), TextDirection.ltr);
    });
  });
}
