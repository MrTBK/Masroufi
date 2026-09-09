import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/analytics/summary.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/dashboard/dashboard_page.dart'
    show buildCalendarWeeks;
import 'package:masroufi/features/onboarding/onboarding_page.dart';
import 'package:masroufi/features/transactions/filter_sheet.dart'
    show activeFilterCount;
import 'package:masroufi/features/transactions/txn_sheets.dart';

/// Phase 2–4 product UX tests: daily guidance math, calendar grid,
/// detail/menu sheets, delete-undo, date badge, 2-step onboarding.
/// In-memory DBs; no device needed.
void main() {
  AppDb mem() => AppDb.forTesting(NativeDatabase.memory());

  group('dailyGuidance', () {
    test('spreads remaining over days left including today', () {
      // Sept 2026: 30 days. On the 11th, 20 days left.
      final g = dailyGuidance(
        budgetMillimes: 2000000,
        spentMillimes: 1260000,
        now: DateTime(2026, 9, 11),
      );
      expect(g.remaining, 740000);
      expect(g.daysLeft, 20);
      expect(g.suggested, 37000);
    });

    test('last day divides by one; over budget stays negative', () {
      final last = dailyGuidance(
        budgetMillimes: 100000,
        spentMillimes: 40000,
        now: DateTime(2026, 9, 30),
      );
      expect(last.daysLeft, 1);
      expect(last.suggested, 60000);
      final over = dailyGuidance(
        budgetMillimes: 100000,
        spentMillimes: 150000,
        now: DateTime(2026, 9, 10),
      );
      expect(over.remaining, -50000);
      expect(over.suggested, lessThan(0));
    });

    test('february boundaries use real month length', () {
      final feb = dailyGuidance(
        budgetMillimes: 28000,
        spentMillimes: 0,
        now: DateTime(2026, 2, 1),
      );
      expect(feb.daysLeft, 28);
      expect(feb.suggested, 1000);
    });
  });

  group('buildCalendarWeeks', () {
    test('september 2026 monday-start pads one leading cell', () {
      // 2026-09-01 is a Tuesday.
      final weeks = buildCalendarWeeks(DateTime(2026, 9, 1), DateTime.monday);
      expect(weeks.length, 5);
      for (final w in weeks) {
        expect(w, hasLength(7));
      }
      expect(weeks.first.first, isNull);
      expect(weeks.first[1], DateTime(2026, 9, 1));
      final days = weeks.expand((w) => w).whereType<DateTime>().toList();
      expect(days, hasLength(30));
      expect(days.last, DateTime(2026, 9, 30));
      expect(weeks.last.last, isNull); // trailing pad cells
    });

    test('sunday start shifts padding; february fits exactly', () {
      final sun = buildCalendarWeeks(DateTime(2026, 9, 1), DateTime.sunday);
      // Tuesday with Sunday start → 2 leading nulls.
      expect(sun.first.take(2), everyElement(isNull));
      // 2026-02-01 is a Sunday: no padding, exactly 4 rows.
      final feb = buildCalendarWeeks(DateTime(2026, 2, 1), DateTime.sunday);
      expect(feb.length, 4);
      expect(feb.first.first, DateTime(2026, 2, 1));
      expect(feb.last.last, DateTime(2026, 2, 28));
    });
  });

  group('activeFilterCount', () {
    test('date window counts as one', () {
      expect(
        activeFilterCount(
          type: null,
          walletId: null,
          catId: null,
          search: '',
          hasDateRange: true,
        ),
        1,
      );
      expect(
        activeFilterCount(
          type: 'expense',
          walletId: 'w',
          catId: 'c',
          search: 'x',
          hasDateRange: true,
        ),
        5,
      );
    });
  });

  group('transaction sheets', () {
    Wallet wallet() => Wallet(
      id: 'w1',
      name: 'Cash',
      icon: 'cash',
      initialMillimes: 100000,
      currency: 'TND',
      isArchived: false,
      isBalanceHidden: false,
      colorKey: 'teal',
      design: 'classic',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    Category category() => Category(
      id: 'c1',
      nameKey: 'cat_cafe',
      customName: null,
      icon: 'coffee',
      kind: 'expense',
      priority: 'normal',
      isArchived: false,
      sortOrder: 0,
      parentId: null,
      createdAt: DateTime(2026, 1, 1),
    );

    Transaction txn() => Transaction(
      id: 't1',
      type: 'expense',
      amountMillimes: 5500,
      walletId: 'w1',
      toWalletId: null,
      categoryId: 'c1',
      recurringRuleId: null,
      occurredAt: DateTime(2026, 9, 8, 22, 57),
      note: 'Coffee with friends',
      createdAt: DateTime(2026, 9, 8, 22, 57),
      updatedAt: DateTime(2026, 9, 8, 22, 57),
    );

    testWidgets('detail sheet shows icon, amount, meta, edit entry', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          home: Consumer(
            builder: (c, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showTxnDetail(
                  c,
                  ref,
                  t: txn(),
                  wallets: [wallet()],
                  cats: [category()],
                  lang: 'en',
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('OPEN'));
      await t.pumpAndSettle();
      expect(find.text('Coffee with friends'), findsWidgets);
      expect(find.textContaining('5.500'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Save as template'), findsOneWidget);
    });

    testWidgets('long-press menu lists edit/duplicate/copy/delete', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Consumer(
            builder: (c, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showTxnMenu(
                  c,
                  ref,
                  t: txn(),
                  wallets: [wallet()],
                  cats: [category()],
                  lang: 'en',
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('OPEN'));
      await t.pumpAndSettle();
      for (final label in ['Edit', 'Duplicate', 'Copy', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('delete shows snackbar; undo restores exact row', (t) async {
      final db = mem();
      addTearDown(db.close);
      final wallets = WalletsRepo(db);
      final txns = TransactionsRepo(db);
      final cash = await wallets.create(name: 'Cash', initialMillimes: 100000);
      final id = await txns.addExpense(
        amountMillimes: 12500,
        walletId: cash,
        note: 'Café',
      );
      final row = (await txns.get(id))!;
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (c, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => deleteTxnWithUndo(c, ref, row),
                  child: const Text('DEL'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('DEL'));
      await t.pumpAndSettle();
      expect(await txns.get(id), isNull);
      expect(find.text('Transaction deleted'), findsOneWidget);
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      final restored = await txns.get(id);
      expect(restored, isNotNull);
      expect(restored!.note, 'Café');
      expect(restored.occurredAt, row.occurredAt);
    });
  });

  group('onboarding', () {
    testWidgets('two steps: language then wallet, theme stays system', (
      t,
    ) async {
      final db = mem();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingPage(),
          ),
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HOME')),
          ),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await t.pumpAndSettle();
      // Step 1: language (default en).
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      // Step 2: wallet directly (no theme step anywhere).
      expect(find.text('Wallet name'), findsOneWidget);
      expect(find.text('Choose appearance'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextField, 'Starting balance'),
        '500',
      );
      await t.tap(find.text('Get started'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      final wallets = await WalletsRepo(db).all();
      expect(wallets, hasLength(1));
      expect(await WalletsRepo(db).balance(wallets.single), 500000);
    });
  });
}
