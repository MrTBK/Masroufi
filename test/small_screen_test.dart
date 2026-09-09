import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/recurring_repo.dart';
import 'package:masroufi/data/repositories/templates_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/dashboard/dashboard_page.dart';
import 'package:masroufi/features/transactions/transactions_page.dart';
import 'package:masroufi/features/transactions/txn_form_page.dart';
import 'package:masroufi/features/wallets/wallets_page.dart';

/// Small-screen layout QA (§52/§57): 360x640 logical px (720p @2x).
/// Flutter fails tests on RenderFlex overflow, so scrolling every
/// surface end-to-end here IS the no-clipping proof. Seeded Arabic
/// (RTL) where direction matters most, English light elsewhere.
void main() {
  // 720x1440 @2.0 → 360x640 logical: small Android phone.
  void smallSurface(WidgetTester t) {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<ProviderContainer> seed({
    required String lang,
    bool withBudget = false,
    bool withRule = false,
    bool withTemplate = false,
  }) async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    final cats = CategoriesRepo(db);
    await cats.seedDefaults();
    final wallets = WalletsRepo(db);
    final txns = TransactionsRepo(db);
    final cash = await wallets.create(name: 'Cash', initialMillimes: 1000000);
    await wallets.create(name: 'Bank', initialMillimes: 250000);
    final all = await cats.all();
    final cafe = all.firstWhere((c) => c.nameKey == 'cat_cafe').id;
    final taxi = all.firstWhere((c) => c.nameKey == 'cat_taxi').id;
    final now = DateTime.now();
    await txns.addExpense(
      amountMillimes: 5500,
      walletId: cash,
      categoryId: cafe,
      note: 'Coffee with friends',
      when: now,
    );
    await txns.addExpense(
      amountMillimes: 12000,
      walletId: cash,
      categoryId: taxi,
      when: now.subtract(const Duration(days: 1, hours: 2)),
    );
    await txns.addIncome(amountMillimes: 500000, walletId: cash, when: now);
    if (withBudget) {
      await BudgetsRepo(db).upsert(now.year, now.month, 2000000);
    }
    if (withRule) {
      await RecurringRepo(db).create(
        type: 'expense',
        amountMillimes: 45000,
        walletId: cash,
        categoryId: cafe,
        note: 'Internet',
        frequency: 'monthly',
        startDate: DateTime(now.year, now.month, 1),
      );
    }
    if (withTemplate) {
      await TemplatesRepo(db).create(
        name: 'Morning coffee',
        type: 'expense',
        amountMillimes: 5500,
        walletId: cash,
        categoryId: cafe,
      );
    }
    container.read(languageProvider.notifier).state = lang;
    return container;
  }

  Future<void> pumpPage(
    WidgetTester t,
    ProviderContainer container,
    Widget page,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => page),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const DashboardPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('SETTINGS')),
        ),
        GoRoute(
          path: '/settings/recurring',
          builder: (_, _) => const Scaffold(body: Text('RECURRING')),
        ),
        GoRoute(
          path: '/add',
          builder: (_, _) =>
              const TxnFormPage(initialType: 'expense'),
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
  }

  /// Main vertical list finder (dashboard/home have exactly one).
  Finder mainList() => find.byWidgetPredicate(
    (w) => w is Scrollable && w.axis == Axis.vertical,
  );

  /// Drag the main vertical list to the very bottom (and back), so
  /// lazily-built sections all lay out at 360px wide.
  /// NOTE: offscreen sections unmount outside the cache extent, so callers
  /// must assert bottom content BEFORE scrolling back up.
  Future<void> scrollThrough(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.drag(mainList().first, const Offset(0, -500));
      await t.pumpAndSettle();
    }
    for (var i = 0; i < 12; i++) {
      await t.drag(mainList().first, const Offset(0, 500));
      await t.pumpAndSettle();
    }
  }

  /// Unmount the tree inside the test body, then let Drift's
  /// zero-duration stream-cleanup timer fire. Without this, pages
  /// holding repo.watch() streams (wallets, categories) fail teardown
  /// with "timer still pending" — a test-harness race, not app code.
  Future<void> unmountClean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 100));
  }

  group('small screens 360x640', () {
    testWidgets('transactions home Arabic RTL, budget+data', (t) async {
      smallSurface(t);
      final container = await seed(
        lang: 'ar',
        withBudget: true,
      );
      await pumpPage(t, container, const TransactionsPage());
      await scrollThrough(t);
      // Hero, comparisons, timeline, day total, guidance all laid out.
      expect(find.text('مصروفي'), findsWidgets);
      expect(find.text('معاملات اليوم'), findsWidgets);
      expect(find.text('إجمالي اليوم'), findsWidgets);
      expect(find.text('الفلاتر'), findsOneWidget);
      expect(find.textContaining('اليومي المقترح'), findsWidgets);
      await unmountClean(t);
    });

    testWidgets('dashboard Arabic with insights+calendar+upcoming', (t) async {
      smallSurface(t);
      final container = await seed(
        lang: 'ar',
        withBudget: true,
        withRule: true,
      );
      await pumpPage(t, container, const DashboardPage());
      // scrollUntilVisible lays every section out at 360px: any
      // overflow fails the test right here. (The calendar header
      // carries the month suffix, so match by containment.)
      await t.scrollUntilVisible(
        find.textContaining('التقويم'),
        500,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );
      expect(find.textContaining('التقويم'), findsWidgets);
      expect(find.text('رؤى'), findsWidgets);
      expect(find.text('القادم'), findsWidgets);
      await unmountClean(t);
    });

    testWidgets('wallets English light cards', (t) async {
      smallSurface(t);

      final container = await seed(lang: 'en');
      await pumpPage(t, container, const WalletsPage());
      await t.pumpAndSettle();
      expect(find.text('CASH'), findsWidgets);
      expect(find.text('BANK'), findsWidgets);
      await unmountClean(t);
    });

    testWidgets('expense form with templates+recents, no clipping', (t) async {
      smallSurface(t);
      final container = await seed(lang: 'en', withTemplate: true);
      await pumpPage(t, container, const TxnFormPage(initialType: 'expense'));
      await t.pumpAndSettle();
      expect(find.text('Morning coffee'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      // Title + save button share the label; both laid out = no clip.
      expect(find.text('Add expense'), findsWidgets);
      await unmountClean(t);
    });
  });
}
