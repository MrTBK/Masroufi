import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/icons/category_icons.dart';
import 'package:masroufi/core/icons/category_visuals.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/core/widgets/design.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/settings_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

void main() {
  group('CategoryVisuals', () {
    test('same key resolves deterministically', () {
      for (final key in CategoryIcons.all) {
        final a = CategoryVisuals.visualFor(key);
        final b = CategoryVisuals.visualFor(key);
        expect(a.lightBg, b.lightBg, reason: key);
        expect(a.lightFg, b.lightFg, reason: key);
        expect(a.darkBg, b.darkBg, reason: key);
        expect(a.darkFg, b.darkFg, reason: key);
      }
    });

    test('foreground differs from background in both modes', () {
      final keys = <String>{
        ...CategoryIcons.all,
        for (final e in Strings.defaultCategories) e.$2,
        for (final e in Strings.defaultIncomeCategories) e.$2,
        'transfer',
      };
      for (final key in keys) {
        final v = CategoryVisuals.visualFor(key);
        expect(v.lightFg, isNot(v.lightBg), reason: 'light $key');
        expect(v.darkFg, isNot(v.darkBg), reason: 'dark $key');
      }
    });

    test('unknown keys fall back without crashing', () {
      final v = CategoryVisuals.visualFor('no_such_icon');
      expect(v.lightBg, isNotNull);
      expect(CategoryIcons.iconFor('no_such_icon'), Icons.category);
    });
  });

  group('income/expense category kinds', () {
    late AppDb db;
    late CategoriesRepo cats;
    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      cats = CategoriesRepo(db);
    });
    tearDown(() => db.close());

    test('seed creates 29 expense + 8 income defaults', () async {
      await cats.seedDefaults();
      final allCats = await cats.all();
      expect(allCats.length, 37);
      expect(allCats.where((c) => c.kind == 'income').length, 8);
      expect(allCats.where((c) => c.kind == 'expense').length, 29);
      // Income defaults carry income icons, resolved by the registry.
      for (final c in allCats.where((c) => c.kind == 'income')) {
        expect(CategoryIcons.isKnown(c.icon), isTrue, reason: '${c.nameKey}');
      }
    });

    test('seed is idempotent and backfills income on upgrade', () async {
      // Simulate a v2 database: expense rows only, no income rows.
      var order = 0;
      for (final (key, icon) in Strings.defaultCategories) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion(
                id: Value('old-$key'),
                nameKey: Value(key),
                icon: Value(icon),
                kind: const Value('expense'),
                sortOrder: Value(order++),
              ),
            );
      }
      await cats.seedDefaults();
      final allCats = await cats.all();
      expect(allCats.length, 37);
      await cats.seedDefaults();
      expect((await cats.all()).length, 37);
    });

    test('kind filter separates expense and income', () async {
      await cats.seedDefaults();
      final income = await cats.all(
        includeArchived: false,
        kinds: const ['income'],
      );
      final expense = await cats.all(
        includeArchived: false,
        kinds: const ['expense'],
      );
      expect(income.length, 8);
      expect(expense.length, 29);
      expect(income.any((c) => c.nameKey == 'cat_cafe'), isFalse);
      expect(expense.any((c) => c.nameKey == 'inc_salary'), isFalse);
    });

    test('custom categories accept both kinds', () async {
      await cats.seedDefaults();
      await cats.create('Side hustle', kind: 'income');
      await cats.create('Pets', kind: 'expense');
      final income = await cats.all(kinds: const ['income']);
      expect(income.any((c) => c.customName == 'Side hustle'), isTrue);
      expect(income.any((c) => c.customName == 'Pets'), isFalse);
    });
  });

  group('wallet balance privacy', () {
    late AppDb db;
    late WalletsRepo wallets;
    late TransactionsRepo txns;
    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      wallets = WalletsRepo(db);
      txns = TransactionsRepo(db);
    });
    tearDown(() => db.close());

    test('hidden flag persists and never changes math', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 100000);
      final bank = await wallets.create(name: 'Bank', initialMillimes: 0);
      await txns.addExpense(
        amountMillimes: 25000,
        walletId: cash,
        categoryId: null,
      );
      final before = await wallets.totalBalance();
      expect(before, 75000);

      await wallets.setBalanceHidden(cash, true);
      expect((await wallets.get(cash))?.isBalanceHidden, isTrue);

      // Totals include hidden wallets: display masking is UI-only.
      expect(await wallets.totalBalance(), before);
      final w = (await wallets.get(cash))!;
      expect(await wallets.balance(w), 75000);

      await wallets.setBalanceHidden(cash, false);
      expect((await wallets.get(cash))?.isBalanceHidden, isFalse);
      expect((await wallets.get(bank))?.isBalanceHidden, isFalse);
    });

    test('new wallets default to visible balances', () async {
      final id = await wallets.create(name: 'Cash');
      expect((await wallets.get(id))?.isBalanceHidden, isFalse);
    });

    test('global hide switch round-trips', () async {
      final settings = SettingsRepo(db);
      expect(await settings.hideBalances(), isFalse);
      await settings.setHideBalances(true);
      expect(await settings.hideBalances(), isTrue);
      await settings.setHideBalances(false);
      expect(await settings.hideBalances(), isFalse);
    });
  });

  group('localization parity for refinement strings', () {
    const keys = [
      'payFrom',
      'moneyGoesTo',
      'incomeCategory',
      'expenseCategories',
      'incomeCategories',
      'categoryKind',
      'hideBalance',
      'showBalance',
      'hiddenBalance',
      'privacy',
      'showBalances',
      'money',
      'analysis',
      'data',
      'customization',
      'parentCategory',
      'noParent',
      'subcategory',
      'subcategories',
      'hasChildrenDeleteBlocked',
      'selectCategory',
      'useThisCategory',
      'moreDetails',
      'last3Months',
      'net',
      'uncategorized',
      'viewAll',
      'welcomeTitle',
      'welcomeBody',
      'addFirstExpense',
      'moveUp',
      'moveDown',
    ];
    test('every new key exists in en/fr/ar and is non-empty', () {
      for (final lang in ['en', 'fr', 'ar']) {
        for (final k in keys) {
          final v = Strings.get(lang, k);
          expect(v, isNotEmpty, reason: '$lang/$k');
          expect(v, isNot(k), reason: '$lang/$k falls back to key');
        }
      }
    });

    test('income names translated everywhere', () {
      for (final (key, _) in Strings.defaultIncomeCategories) {
        for (final lang in ['en', 'fr', 'ar']) {
          expect(
            Strings.categoryNames[lang]?[key],
            isNotNull,
            reason: '$lang/$key',
          );
        }
      }
    });

    test('parent names translated everywhere', () {
      for (final (key, _, _) in Strings.defaultParentCategories) {
        for (final lang in ['en', 'fr', 'ar']) {
          final v = Strings.categoryNames[lang]?[key];
          expect(v, isNotNull, reason: '$lang/$key');
          expect(v, isNotEmpty, reason: '$lang/$key');
        }
      }
    });

    test('moneyGoesTo uses natural translations', () {
      expect(Strings.get('en', 'moneyGoesTo'), 'Money goes to');
      expect(Strings.get('fr', 'moneyGoesTo'), 'Argent vers');
      expect(Strings.get('ar', 'moneyGoesTo'), 'ستذهب الأموال إلى');
    });
  });

  group('privacy widgets', () {
    testWidgets('IconPickerGrid marks exactly one selection', (tester) async {
      var selected = 'cash';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setS) => IconPickerGrid(
                keys: const ['cash', 'bank', 'card'],
                selected: selected,
                onSelected: (k) => setS(() => selected = k),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
      final bankIcon = find.byWidgetPredicate(
        (w) => w is Icon && w.icon != Icons.check && w.semanticLabel == 'bank',
      );
      expect(bankIcon, findsOneWidget);
      await tester.tap(bankIcon);
      await tester.pump();
      expect(selected, 'bank');
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('WalletSelectCard masks hidden balances', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletSelectCard(
              iconKey: 'cash',
              name: 'Cash',
              balanceMillimes: 579500,
              masked: true,
              lang: 'en',
              maskedLabel: 'Hidden balance',
              selected: true,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.textContaining('579'), findsNothing);
    });

    testWidgets('CategoryListTile renders in Arabic RTL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
          home: Scaffold(
            body: CategoryListTile(
              iconKey: 'coffee',
              title: 'مقهى',
              trailing: const Icon(Icons.more_vert),
            ),
          ),
        ),
      );
      expect(find.text('مقهى'), findsOneWidget);
      final ctx = tester.element(find.text('مقهى'));
      expect(Directionality.of(ctx), TextDirection.rtl);
    });
  });
}
