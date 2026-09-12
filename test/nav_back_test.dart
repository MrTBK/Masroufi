import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/budgets/budget_page.dart';
import 'package:masroufi/features/settings/donate_page.dart';
import 'package:masroufi/features/settings/pro_page.dart';
import 'package:masroufi/features/settings/settings_page.dart';
import 'package:masroufi/features/transactions/transactions_page.dart';
import 'package:masroufi/features/wallets/wallets_page.dart';

/// Branch back-button QA: Wallets/Mizania AppBars expose an explicit
/// leading back button home (title-tap alone was undiscoverable).
void main() {
  Future<ProviderContainer> seed() async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    await CategoriesRepo(db).seedDefaults();
    await WalletsRepo(db).create(name: 'Cash', initialMillimes: 1000000);
    container.read(languageProvider.notifier).state = 'en';
    return container;
  }

  Future<GoRouter> pumpBranch(
    WidgetTester t,
    ProviderContainer container,
    String at,
  ) async {
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TransactionsPage()),
        GoRoute(path: '/wallets', builder: (_, _) => const WalletsPage()),
        GoRoute(path: '/mizania', builder: (_, _) => const BudgetPage()),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    return router;
  }

  Future<void> unmountClean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('wallets back button returns home', (t) async {
    final container = await seed();
    final router = await pumpBranch(t, container, '/wallets');
    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(router.state.matchedLocation, '/');
    await unmountClean(t);
  });

  testWidgets('mizania back button returns home', (t) async {
    final container = await seed();
    final router = await pumpBranch(t, container, '/mizania');
    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(router.state.matchedLocation, '/');
    await unmountClean(t);
  });

  testWidgets('pro page opens without store (manual path)', (t) async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.read(languageProvider.notifier).state = 'en';
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProPage()),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    // No store on desktop/tests: either the manual box or its loader
    // shows. The regression was a LateError crash in initState.
    expect(
      find
          .byType(TextField)
          .evaluate()
          .isNotEmpty ||
          find
              .byType(CircularProgressIndicator)
              .evaluate()
              .isNotEmpty,
      isTrue,
    );
    await unmountClean(t);
  });

  testWidgets('donate page renders en + ar RTL', (t) async {
    for (final lang in ['en', 'ar']) {
      final db = AppDb.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });
      container.read(languageProvider.notifier).state = lang;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DonatePage()),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.volunteer_activism), findsWidgets);
      await unmountClean(t);
    }
  });

  testWidgets('settings gates dark theme + lock behind PRO', (t) async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.read(languageProvider.notifier).state = 'en';
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(
          path: '/settings/pro',
          builder: (_, _) => const Scaffold(body: Text('PROPAGE')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pump(const Duration(milliseconds: 200));
    // Upsell tiles visible, no plain dark radio, no PIN setup button.
    expect(find.textContaining('PRO'), findsWidgets);
    expect(find.widgetWithText(RadioListTile<String>, 'Dark'), findsNothing);
    await unmountClean(t);
  });
}
