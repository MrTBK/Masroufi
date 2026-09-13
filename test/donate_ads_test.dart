import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/features/settings/donate_page.dart';

Future<void> unmountClean(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpDonate(
  WidgetTester t, {
  required Future<bool> Function() online,
}) async {
  final db = AppDb.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      appDbProvider.overrideWithValue(db),
      onlineCheckProvider.overrideWithValue(online),
    ],
  );
  addTearDown(() {
    container.dispose();
    db.close();
  });
  container.read(languageProvider.notifier).state = 'en';
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DonatePage()),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  group('donate ads connectivity', () {
    testWidgets('offline tap explains offline, never blames loading', (
      t,
    ) async {
      await _pumpDonate(t, online: () async => false);
      await t.tap(find.text(Strings.get('en', 'donateWatch')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(
        find.text(Strings.get('en', 'donateOffline')),
        findsWidgets,
      );
      expect(find.text(Strings.get('en', 'donateAdNotReady')), findsNothing);
      await unmountClean(t);
    });

    testWidgets('online tap without fill says not-ready, not offline', (
      t,
    ) async {
      await _pumpDonate(t, online: () async => true);
      await t.tap(find.text(Strings.get('en', 'donateWatch')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text(Strings.get('en', 'donateAdNotReady')), findsOneWidget);
      expect(find.text(Strings.get('en', 'donateOffline')), findsNothing);
      await unmountClean(t);
    });
  });
}
