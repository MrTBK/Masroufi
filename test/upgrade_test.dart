import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/analytics/periods.dart';
import 'package:masroufi/core/widget/masroufi_widget.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/settings_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/dashboard/dashboard_page.dart';

/// Phase A upgrade tests: quick-add history signals, wallet statistics,
/// last-backup timestamp, dashboard income hero + insights wiring.
void main() {
  AppDb mem() => AppDb.forTesting(NativeDatabase.memory());

  group('quick-add category signals', () {
    late AppDb db;
    late TransactionsRepo txns;
    late CategoriesRepo cats;
    late String cash;
    late String cafe;
    late String taxi;
    setUp(() async {
      db = mem();
      txns = TransactionsRepo(db);
      cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final all = await cats.all();
      cafe = all.firstWhere((c) => c.nameKey == 'cat_cafe').id;
      taxi = all.firstWhere((c) => c.nameKey == 'cat_taxi').id;
      cash = await WalletsRepo(db).create(name: 'Cash');
    });
    tearDown(() => db.close());

    test('recentCategoryIds orders by recency, skips nulls/transfers',
        () async {
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: cafe,
        when: DateTime(2026, 1, 1),
      );
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: taxi,
        when: DateTime(2026, 2, 1),
      );
      await txns.addExpense(amountMillimes: 1000, walletId: cash);
      final bank = await WalletsRepo(db).create(name: 'Bank');
      await txns.addTransfer(
        amountMillimes: 500,
        fromWalletId: cash,
        toWalletId: bank,
      );
      expect(
        await txns.recentCategoryIds(type: 'expense'),
        [taxi, cafe],
      );
      expect(await txns.recentCategoryIds(type: 'income'), isEmpty);
    });

    test('frequentCategoryIds counts the window, ties break by recency',
        () async {
      final now = DateTime.now();
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: cafe,
        when: now.subtract(const Duration(days: 2)),
      );
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: cafe,
        when: now.subtract(const Duration(days: 1)),
      );
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: taxi,
        when: now,
      );
      // Ancient use outside the default 30-day window is ignored.
      await txns.addExpense(
        amountMillimes: 1000,
        walletId: cash,
        categoryId: taxi,
        when: now.subtract(const Duration(days: 90)),
      );
      expect(
        await txns.frequentCategoryIds(type: 'expense'),
        [cafe, taxi],
      );
    });
  });

  group('walletStats', () {
    test('month flows + count, transfers on both endpoints', () async {
      final db = mem();
      addTearDown(db.close);
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final analytics = AnalyticsRepo(db);
      final cash = await wallets.create(name: 'Cash');
      final bank = await wallets.create(name: 'Bank');
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      await txns.addIncome(
        amountMillimes: 500000,
        walletId: cash,
        when: start.add(const Duration(hours: 1)),
      );
      await txns.addExpense(
        amountMillimes: 120000,
        walletId: cash,
        when: start.add(const Duration(hours: 2)),
      );
      await txns.addTransfer(
        amountMillimes: 100000,
        fromWalletId: cash,
        toWalletId: bank,
        when: start.add(const Duration(hours: 3)),
      );
      // Previous month: invisible to the window.
      await txns.addExpense(
        amountMillimes: 999000,
        walletId: cash,
        when: start.subtract(const Duration(days: 1)),
      );
      final s = await analytics.walletStats(cash, start, end);
      expect(s.income, 500000);
      expect(s.expense, 120000);
      expect(s.tIn, 0);
      expect(s.tOut, 100000);
      expect(s.count, 3);
      final b = await analytics.walletStats(bank, start, end);
      expect(b.tIn, 100000);
      expect(b.count, 1);
    });
  });

  group('lastBackupAt', () {
    test('null until set, round-trips, garbage is null', () async {
      final db = mem();
      addTearDown(db.close);
      final settings = SettingsRepo(db);
      expect(await settings.lastBackupAt(), isNull);
      final when = DateTime.utc(2026, 9, 8, 12, 30);
      await settings.setLastBackupAt(when);
      expect(await settings.lastBackupAt(), when);
      await settings.set('last_backup_at', 'not-a-date');
      expect(await settings.lastBackupAt(), isNull);
    });
  });

  group('dashboard income hero + insights', () {
    testWidgets('shows period income and deterministic insight lines',
        (t) async {
      final db = mem();
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final cash = await wallets.create(
        name: 'Cash',
        initialMillimes: 1000000,
      );
      final all = await cats.all();
      final cafe = all.firstWhere((c) => c.nameKey == 'cat_cafe').id;
      final now = DateTime.now();
      final prevStart = Periods.lastMonth(now).start;
      DateTime at(DateTime monthStart, int day) =>
          DateTime(monthStart.year, monthStart.month, day, 12);
      await txns.addExpense(
        amountMillimes: 100000,
        walletId: cash,
        categoryId: cafe,
        when: at(DateTime(now.year, now.month, 1), 5),
      );
      await txns.addExpense(
        amountMillimes: 50000,
        walletId: cash,
        categoryId: cafe,
        when: at(prevStart, 5),
      );
      await txns.addIncome(
        amountMillimes: 500000,
        walletId: cash,
        when: at(DateTime(now.year, now.month, 1), 3),
      );
      await txns.addIncome(
        amountMillimes: 400000,
        walletId: cash,
        when: at(prevStart, 3),
      );
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await t.pumpAndSettle();
      // Income hero for the selected (current-month) period.
      expect(find.textContaining('500.000'), findsWidgets);
      // Insights live at the bottom of a lazily-built ListView: scroll
      // until they materialize (proves real wiring, not just data).
      // Explicit scrollable: the page also hosts the horizontal period
      // chips strip, and the helper requires exactly one candidate.
      await t.scrollUntilVisible(
        find.textContaining('more this month'),
        500,
        // The helper wants the inner Scrollable (not the ListView) and
        // exactly one candidate: the main list is the only vertical one
        // (the period chips strip scrolls horizontally).
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );
      // MoM insight: 100k vs 50k → deterministic +100% line.
      expect(find.textContaining('more this month'), findsOneWidget);
      // Top-category insight names the rolled-up parent (analytics level;
      // leaf names like Café appear on transactions, never in rollups).
      expect(find.textContaining('Food & Drinks'), findsWidgets);
    });
  });

  group('home widget data', () {
    test('widgetLines localizes + isolates amounts for launchers', () {
      final en = widgetLines(
        totalMillimes: 1250000,
        todaySpentMillimes: 0,
        lang: 'en',
      );
      expect(en.title, 'Masroufi');
      expect(en.balance, contains('1,250.000 TND'));
      final ar = widgetLines(
        totalMillimes: -4420500,
        todaySpentMillimes: 5500,
        lang: 'ar',
      );
      expect(ar.title, 'مصروفي');
      // Bidi isolates (not raw text) keep the minus attached in
      // launcher TextViews — same bug class as §8, same fix.
      expect(ar.balance, startsWith('\u2066'));
      expect(ar.balance, endsWith('\u2069'));
      expect(ar.balance, contains('-4,420.500 د.ت'));
      expect(ar.today, contains('اليوم'));
      expect(ar.today, contains('5.500 د.ت'));
    });
  });
}
