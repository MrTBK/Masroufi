import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/periods.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/database/category_hierarchy.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/transactions/category_picker.dart';

/// Acceptance flow (§22): Cash 500 → Café 12.500 → Restaurant 20 →
/// Taxi 8, with dashboard rollups verified at each step.
void main() {
  group('expense acceptance flow', () {
    late AppDb db;
    late WalletsRepo wallets;
    late CategoriesRepo cats;
    late TransactionsRepo txns;
    late AnalyticsRepo analytics;
    late String cashId;
    late Map<String, String> idByKey;

    setUp(() async {
      db = AppDb.forTesting(NativeDatabase.memory());
      wallets = WalletsRepo(db);
      cats = CategoriesRepo(db);
      txns = TransactionsRepo(db);
      analytics = AnalyticsRepo(db);
      await cats.seedDefaults();
      final all = await cats.all();
      idByKey = {for (final c in all) c.nameKey!: c.id};
      cashId = await wallets.create(name: 'Cash', initialMillimes: 500000);
    });
    tearDown(() => db.close());

    Future<int> balance() async =>
        wallets.balance((await wallets.get(cashId))!);

    Future<int> foodTotal(DateTime now) async {
      final range = Periods.month(now);
      final byCat = await analytics.expenseByCategory(range.start, range.end);
      final rolled = CategoryHierarchy.rollUp(byCat, await cats.all());
      return rolled[idByKey['cat_food_drinks']] ?? 0;
    }

    test('cash 500, cafe 12.500 leaves 487.500', () async {
      final now = DateTime.now();
      await txns.addExpense(
        amountMillimes: 12500,
        walletId: cashId,
        categoryId: idByKey['cat_cafe'],
        when: now,
      );
      expect(await balance(), 487500);
      expect(await foodTotal(now), 12500);
    });

    test('restaurant 20 rolls food up to 32.500 with child split', () async {
      final now = DateTime.now();
      final base = DateTime(now.year, now.month, 15, 12);
      await txns.addExpense(
        amountMillimes: 12500,
        walletId: cashId,
        categoryId: idByKey['cat_cafe'],
        when: base,
      );
      await txns.addExpense(
        amountMillimes: 20000,
        walletId: cashId,
        categoryId: idByKey['cat_restaurants'],
        when: base.add(const Duration(seconds: 1)),
      );
      expect(await balance(), 467500);
      expect(await foodTotal(now), 32500);
      final range = Periods.month(now);
      final byCat = await analytics.expenseByCategory(range.start, range.end);
      expect(byCat[idByKey['cat_cafe']], 12500);
      expect(byCat[idByKey['cat_restaurants']], 20000);
    });

    test('taxi 8 lands under transport, food untouched', () async {
      final now = DateTime.now();
      final base = DateTime(now.year, now.month, 15, 12);
      await txns.addExpense(
        amountMillimes: 12500,
        walletId: cashId,
        categoryId: idByKey['cat_cafe'],
        when: base,
      );
      await txns.addExpense(
        amountMillimes: 20000,
        walletId: cashId,
        categoryId: idByKey['cat_restaurants'],
        when: base.add(const Duration(seconds: 1)),
      );
      await txns.addExpense(
        amountMillimes: 8000,
        walletId: cashId,
        categoryId: idByKey['cat_taxi'],
        when: base.add(const Duration(seconds: 2)),
      );
      final range = Periods.month(now);
      final rolled = CategoryHierarchy.rollUp(
        await analytics.expenseByCategory(range.start, range.end),
        await cats.all(),
      );
      expect(rolled[idByKey['cat_food_drinks']], 32500);
      expect(rolled[idByKey['cat_transport']], 8000);
      // Recent-first ordering with the right leaf icons.
      final recent = await txns.list(const TxnFilter(limit: 3));
      final all = await cats.all();
      String iconOf(String? id) =>
          all.where((c) => c.id == id).map((c) => c.icon).single;
      expect(iconOf(recent[0].categoryId), 'taxi');
      expect(iconOf(recent[1].categoryId), 'restaurant');
      expect(iconOf(recent[2].categoryId), 'coffee');
    });

    test('period switch moves numbers between ranges', () async {
      final now = DateTime.now();
      final last = DateTime(now.year, now.month - 1, 15);
      await txns.addExpense(
        amountMillimes: 8000,
        walletId: cashId,
        categoryId: idByKey['cat_taxi'],
        when: last,
      );
      final thisRange = Periods.month(now);
      final lastRange = Periods.lastMonth(now);
      expect(await analytics.expenseTotal(thisRange.start, thisRange.end), 0);
      expect(
        await analytics.expenseTotal(lastRange.start, lastRange.end),
        8000,
      );
    });
  });

  group('CategoryPicker sheet', () {
    testWidgets('primaries first, children after drill-in', (tester) async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final visible = await cats.all(
        includeArchived: false,
        kinds: const ['expense'],
      );
      final byId = {for (final c in visible) c.id: c};
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                picked = await showCategoryPicker(
                  context,
                  lang: 'en',
                  visible: visible,
                  byId: byId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Primary step: parents visible, leaves hidden (no flat duplicates).
      expect(find.text('Food & Drinks'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Café'), findsNothing);
      await tester.tap(find.text('Food & Drinks'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Restaurants'), findsOneWidget);
      await tester.tap(find.text('Café'));
      await tester.pumpAndSettle();
      expect(picked, visible.singleWhere((c) => c.nameKey == 'cat_cafe').id);
    });
  });
}
