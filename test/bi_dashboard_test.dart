import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/dashboard/dashboard_page.dart';

/// Dashboard-as-Analytics page test: one snapshot drives KPIs, forecast,
/// drill, budget, and health sections on a 360px surface.
void main() {
  testWidgets('BI sections render from one snapshot', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final db = AppDb.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    await CategoriesRepo(db).seedDefaults();
    final wallets = WalletsRepo(db);
    final txns = TransactionsRepo(db);
    final cash = await wallets.create(name: 'Cash');
    final now = DateTime.now();
    final cats = await CategoriesRepo(db).all();
    final cafe = cats.firstWhere((c) => c.nameKey == 'cat_cafe').id;
    await txns.addExpense(
      amountMillimes: 120000,
      walletId: cash,
      categoryId: cafe,
      when: DateTime(now.year, now.month, 2),
    );
    await txns.addIncome(
      amountMillimes: 1000000,
      walletId: cash,
      when: DateTime(now.year, now.month, 3),
    );
    await BudgetsRepo(db).upsert(now.year, now.month, 500000);
    container.read(languageProvider.notifier).state = 'en';

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const DashboardPage(),
        ),
        GoRoute(
          path: '/dashboard/category/:id',
          builder: (_, _) => const Scaffold(body: Text('DETAIL')),
        ),
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/settings', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/settings/recurring',
          builder: (_, _) => const Scaffold(),
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
    await t.pumpAndSettle();

    // KPI grid ('Savings rate' also labels its health breakdown row).
    expect(find.text('Net cash flow'), findsOneWidget);
    expect(find.text('Savings rate'), findsWidgets);
    // Forecast card (month has spend).
    expect(find.text('Forecast'), findsOneWidget);
    // Drill + wallet + budget + health sections.
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('By wallet'), findsOneWidget);
    expect(find.text('Budget vs actual'), findsOneWidget);
    expect(find.text('Financial health'), findsOneWidget);
    // Filter bar presets.
    expect(find.text('Today'), findsOneWidget);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 100));
  });
}
