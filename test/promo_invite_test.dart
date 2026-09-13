import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/features/settings/donate_page.dart';

Future<void> unmountPromo(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 100));
}

Future<ProviderContainer> _pumpDonate(
  WidgetTester t, {
  bool isPro = false,
}) async {
  final db = AppDb.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      appDbProvider.overrideWithValue(db),
      onlineCheckProvider.overrideWithValue(() async => true),
    ],
  );
  addTearDown(() {
    container.dispose();
    db.close();
  });
  container.read(languageProvider.notifier).state = 'en';
  container.read(isProProvider.notifier).state = isPro;
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DonatePage()),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  group('donate advertise-here slot', () {
    testWidgets('free users see invite card', (t) async {
      await _pumpDonate(t);
      expect(find.text(Strings.get('en', 'promoInviteTitle')), findsOneWidget);
      expect(find.text(Strings.get('en', 'promoInviteBody')), findsOneWidget);
      await unmountPromo(t);
    });

    testWidgets('PRO hides invite card', (t) async {
      await _pumpDonate(t, isPro: true);
      expect(find.text(Strings.get('en', 'promoInviteTitle')), findsNothing);
      await unmountPromo(t);
    });
  });
}
