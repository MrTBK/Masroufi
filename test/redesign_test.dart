import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:masroufi/core/routing/router.dart' show shouldInterceptBack;
import 'package:masroufi/core/analytics/periods.dart';
import 'package:masroufi/core/analytics/summary.dart';
import 'package:masroufi/core/icons/category_icons.dart';
import 'package:masroufi/core/icons/category_visuals.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/core/theme/wallet_styles.dart';
import 'package:masroufi/core/widgets/donut_chart.dart';
import 'package:masroufi/core/widgets/masroufi_nav.dart';
import 'package:masroufi/core/widgets/wallet_card.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/core/utils/dates.dart' show dayGroupHeader;
import 'package:masroufi/features/transactions/filter_sheet.dart'
    show activeFilterCount;

AppDb _mem() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('Periods.txnRangeFor', () {
    final now = DateTime(2026, 9, 8, 14, 30); // a Tuesday
    test('today/yesterday are adjacent single days', () {
      final t = Periods.txnRangeFor('today', now, 'monday');
      final y = Periods.txnRangeFor('yesterday', now, 'monday');
      expect(t.end.difference(t.start), const Duration(days: 1));
      expect(t.start, y.end);
      expect(t.start, DateTime(2026, 9, 8));
    });
    test('thisWeek/lastWeek are adjacent 7-day windows', () {
      final cur = Periods.txnRangeFor('thisWeek', now, 'monday');
      final last = Periods.txnRangeFor('lastWeek', now, 'monday');
      expect(cur.end.difference(cur.start), const Duration(days: 7));
      expect(cur.start, last.end);
      expect(cur.start.weekday, DateTime.monday);
    });
    test('thisMonth/lastMonth are adjacent calendar months', () {
      final cur = Periods.txnRangeFor('thisMonth', now, 'monday');
      final last = Periods.txnRangeFor('lastMonth', now, 'monday');
      expect(cur.start, DateTime(2026, 9, 1));
      expect(cur.end, DateTime(2026, 10, 1));
      expect(last, (start: DateTime(2026, 8, 1), end: DateTime(2026, 9, 1)));
    });
    test('unknown id falls back to thisMonth', () {
      final r = Periods.txnRangeFor('nope', now, 'monday');
      expect(r.start, DateTime(2026, 9, 1));
    });
    test('elapsedDays clamps to >= 1 and caps at period end', () {
      final r = Periods.txnRangeFor('thisMonth', now, 'monday');
      expect(Periods.elapsedDays(r.start, r.end, now), 8);
      final past = Periods.txnRangeFor('lastMonth', now, 'monday');
      expect(Periods.elapsedDays(past.start, past.end, now), 31);
      expect(Periods.elapsedDays(now, now, now), 1);
    });
  });

  group('CategoryIcons registry', () {
    test('spec aliases resolve to real icons (no fallback)', () {
      const aliases = [
        'coffee',
        'taxi',
        'louage',
        'bus',
        'metro',
        'fuel',
        'electricity',
        'steg',
        'water',
        'sonede',
        'internet',
        'wifi',
        'mobile',
        'phone',
        'groceries',
        'shopping_cart',
        'restaurant',
        'clothing',
        'electronics',
        'home',
        'health',
        'entertainment',
        'gym',
        'other',
      ];
      for (final k in aliases) {
        expect(CategoryIcons.isKnown(k), isTrue, reason: k);
      }
      // louage/bus/metro are distinct transport icons.
      expect(
        CategoryIcons.iconFor('bus'),
        isNot(equals(CategoryIcons.iconFor('louage'))),
      );
    });
    test('unknown keys fall back, history never breaks', () {
      expect(
        CategoryIcons.iconFor('legacy_key_xyz'),
        CategoryIcons.iconFor('other'),
      );
      expect(CategoryIcons.iconFor(null), CategoryIcons.iconFor('other'));
    });
    test('all list has no duplicates', () {
      expect(CategoryIcons.all.toSet(), hasLength(CategoryIcons.all.length));
    });
    test('visuals cover aliases in both brightnesses', () {
      for (final k in ['louage', 'metro', 'steg', 'sonede', 'groceries']) {
        expect(CategoryVisuals.visualFor(k), isNotNull, reason: k);
      }
    });
  });

  group('Wallet visibility is mask-only + styling persists', () {
    late AppDb db;
    late WalletsRepo wallets;
    setUp(() {
      db = _mem();
      wallets = WalletsRepo(db);
    });
    tearDown(() => db.close());

    test('hiding never changes balances or totals', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 579500);
      final txns = TransactionsRepo(db);
      await txns.addExpense(amountMillimes: 50000, walletId: cash);
      final before = await wallets.totalBalance();
      await wallets.setBalanceHidden(cash, true);
      final w = await wallets.get(cash);
      expect(w!.isBalanceHidden, isTrue);
      expect(await wallets.balance(w), before);
      expect(await wallets.totalBalance(), before);
    });

    test('hidden is distinct from archived', () async {
      final id = await wallets.create(name: 'Bank', initialMillimes: 1000);
      await wallets.setBalanceHidden(id, true);
      await wallets.setArchived(id, true);
      final w = await wallets.get(id);
      expect(w!.isBalanceHidden, isTrue);
      expect(w.isArchived, isTrue);
      // Archived wallets leave active totals.
      expect(await wallets.totalBalance(), 0);
      await wallets.setArchived(id, false);
      expect(await wallets.totalBalance(), 1000);
    });

    test('colorKey/design round-trip with defaults', () async {
      final id = await wallets.create(name: 'Travel');
      var w = (await wallets.get(id))!;
      expect(w.colorKey, 'teal');
      expect(w.design, 'classic');
      await wallets.setColorKey(id, 'purple');
      await wallets.setDesign(id, 'modern');
      w = (await wallets.get(id))!;
      expect(w.colorKey, 'purple');
      expect(w.design, 'modern');
      expect(WalletStyles.isKnownColor('purple'), isTrue);
      expect(WalletStyles.isKnownDesign('modern'), isTrue);
    });

    test('visibleBalance excludes hidden, totalBalance does not', () async {
      final cash = await wallets.create(name: 'Cash', initialMillimes: 579500);
      final bank = await wallets.create(name: 'Bank', initialMillimes: 100000);
      expect(await wallets.visibleBalance(), 679500);
      await wallets.setBalanceHidden(cash, true);
      // Ledger truth unchanged …
      expect(await wallets.totalBalance(), 679500);
      // … but prominent summaries must not expose the hidden wallet.
      expect(await wallets.visibleBalance(), 100000);
      await wallets.setBalanceHidden(cash, false);
      expect(await wallets.visibleBalance(), 679500);
      expect(bank, isNotEmpty);
    });

    test('visibleBalance excludes archived too', () async {
      final id = await wallets.create(name: 'Old', initialMillimes: 50000);
      await wallets.setArchived(id, true);
      expect(await wallets.visibleBalance(), 0);
      expect(await wallets.totalBalance(), 0);
    });
  });

  group('Today-first headers + filter counts', () {
    test('dayGroupHeader: today label, yesterday, weekday', () async {
      // Mirror main.dart: weekday/month names need symbol data.
      await initializeDateFormatting('ar');
      await initializeDateFormatting('fr');
      final now = DateTime(2026, 9, 8, 14); // a Tuesday
      expect(
        dayGroupHeader(DateTime(2026, 9, 8, 9), now, 'ar'),
        'معاملات اليوم',
      );
      expect(
        dayGroupHeader(DateTime(2026, 9, 8, 9), now, 'en'),
        "Today's transactions",
      );
      expect(
        dayGroupHeader(DateTime(2026, 9, 8, 9), now, 'fr'),
        'Transactions du jour',
      );
      expect(dayGroupHeader(DateTime(2026, 9, 7), now, 'ar'), 'أمس');
      expect(dayGroupHeader(DateTime(2026, 9, 7), now, 'en'), 'YESTERDAY');
      // Older days get locale weekday headers, never M/D digits.
      final old = dayGroupHeader(DateTime(2026, 9, 6), now, 'ar');
      expect(old.contains('/'), isFalse);
      expect(old.isNotEmpty, isTrue);
    });

    test('activeFilterCount tallies set filters', () {
      expect(
        activeFilterCount(type: null, walletId: null, catId: null, search: ''),
        0,
      );
      expect(
        activeFilterCount(
          type: 'expense',
          walletId: null,
          catId: null,
          search: '',
        ),
        1,
      );
      expect(
        activeFilterCount(
          type: 'expense',
          walletId: 'w1',
          catId: 'c1',
          search: 'cafe',
        ),
        4,
      );
    });
  });

  group('FinancialSummaryService + CategorySpendingService', () {
    late AppDb db;
    late WalletsRepo wallets;
    late TransactionsRepo txns;
    late CategoriesRepo cats;
    late AnalyticsRepo analytics;
    setUp(() {
      db = _mem();
      wallets = WalletsRepo(db);
      txns = TransactionsRepo(db);
      cats = CategoriesRepo(db);
      analytics = AnalyticsRepo(db);
    });
    tearDown(() => db.close());

    test('totals, spending, top categories, averages', () async {
      await cats.seedDefaults();
      final allCats = await cats.all();
      String idOf(String key) => allCats.firstWhere((c) => c.nameKey == key).id;
      final cash = await wallets.create(name: 'Cash', initialMillimes: 1000000);
      final now = DateTime(2026, 9, 8, 12);
      await txns.addExpense(
        amountMillimes: 85000,
        walletId: cash,
        categoryId: idOf('cat_cafe'),
        when: DateTime(2026, 9, 8, 9),
      );
      await txns.addExpense(
        amountMillimes: 120000,
        walletId: cash,
        categoryId: idOf('cat_groceries'),
        when: DateTime(2026, 9, 7, 10),
      );
      await txns.addIncome(
        amountMillimes: 500000,
        walletId: cash,
        when: DateTime(2026, 9, 1, 8),
      );
      // Prior completed months for the monthly average.
      await txns.addExpense(
        amountMillimes: 300000,
        walletId: cash,
        when: DateTime(2026, 8, 10, 8),
      );
      await txns.addExpense(
        amountMillimes: 300000,
        walletId: cash,
        when: DateTime(2026, 7, 10, 8),
      );
      await txns.addExpense(
        amountMillimes: 300000,
        walletId: cash,
        when: DateTime(2026, 6, 10, 8),
      );

      final summary = FinancialSummaryService(
        analytics: analytics,
        wallets: wallets,
      );
      final sept = Periods.month(now);
      expect(await summary.spentIn(sept.start, sept.end), 205000);
      expect(await summary.incomeIn(sept.start, sept.end), 500000);
      // initial 1,000,000 - expenses(205k+900k) + income 500k
      expect(await summary.totalMoney(), 1000000 - 1105000 + 500000);

      final avg = await summary.averageSpending(sept.start, sept.end, now);
      expect(avg.days, 8);
      expect(avg.dailyAverage, 205000 ~/ 8);

      final monthly = await summary.monthlyAverage(now);
      expect(monthly.months, 3);
      expect(monthly.monthlyAverage, 300000);

      final spending = CategorySpendingService(analytics: analytics);
      final top = await spending.topCategories(sept.start, sept.end);
      expect(top, hasLength(2));
      expect(top.first.total, 120000);
      expect(top.last.total, 85000);

      // Transfers never leak into income/expense.
      final bank = await wallets.create(name: 'Bank');
      await txns.addTransfer(
        amountMillimes: 100000,
        fromWalletId: cash,
        toWalletId: bank,
      );
      expect(await summary.spentIn(sept.start, sept.end), 205000);
    });

    test('archived category history still resolves', () async {
      await cats.seedDefaults();
      final allCats = await cats.all();
      final cafe = allCats.firstWhere((c) => c.nameKey == 'cat_cafe');
      final cash = await wallets.create(name: 'Cash', initialMillimes: 500000);
      await txns.addExpense(
        amountMillimes: 5500,
        walletId: cash,
        categoryId: cafe.id,
      );
      await cats.setArchived(cafe.id, true);
      final list = await txns.list(const TxnFilter(limit: 10));
      expect(list.single.categoryId, cafe.id);
      final again = await cats.all(includeArchived: true);
      expect(again.firstWhere((c) => c.id == cafe.id).icon, cafe.icon);
    });
  });

  group('l10n parity for redesign keys', () {
    const keys = [
      'mizania',
      'yourMoney',
      'totalMoney',
      'totalSpent',
      'lastWeek',
      'avgSpending',
      'monthlyAverage',
      'moneyIn',
      'moneyOut',
      'moneyInOut',
      'addWallet',
      'walletColor',
      'walletStyle',
      'manageWallets',
      'manageCategories',
      'viewDashboard',
      'viewTransactions',
      'noExpensesYet',
      'dailyAvgNote',
      'monthlyAvgNote',
      'hiddenNote',
      'todayTransactions',
      'filters',
      'clearFilters',
      'loadMore',
      'done',
      'setPin',
      'changePin',
      'removePin',
      'enterPin',
      'confirmPin',
      'pinMismatch',
      'wrongPin',
      'useBiometrics',
      'lockTimeout',
      'lockImmediate',
      'lock1min',
      'lock5min',
      'unlockApp',
      'lastBackup',
      'noBackupYet',
      'importCsv',
      'csvSummary',
      'csvImported',
      'copy',
      'copied',
      'undo',
      'deletedTxn',
      'saveAsTemplate',
      'templates',
      'templateSaved',
      'templateDeleted',
      'dayTotal',
      'dateFilter',
      'dateAll',
      'suggestedDaily',
      'daysLeft',
      'healthWithin',
      'healthOver',
      'healthSecond',
      'healthDays',
      'calendar',
      'notifications',
      'notifBudgetExceeded',
      'notifBudgetWarning',
      'notifCatExceeded',
      'notifCatWarning',
      'notifRecurringDue',
      'notifHighSpending',
      'recentCategories',
      'totalIncome',
    ];
    test('every key translated in en/fr/ar', () {
      for (final k in keys) {
        for (final lang in ['en', 'fr', 'ar']) {
          final v = Strings.get(lang, k);
          expect(v, isNotEmpty, reason: '$lang/$k');
          expect(v, isNot(equals(k)), reason: '$lang/$k');
        }
      }
    });
  });

  group('redesign widgets (light/dark/RTL)', () {
    testWidgets('DonutChart empty state in Arabic RTL', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          locale: Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DonutChart(slices: [], totalMillimes: 0, lang: 'ar'),
            ),
          ),
        ),
      );
      expect(find.text('لا توجد مصاريف في هذه الفترة'), findsOneWidget);
    });

    testWidgets('DonutChart renders total + slices', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DonutChart(
              slices: [
                DonutSlice(
                  id: 'c1',
                  label: 'Café',
                  iconKey: 'coffee',
                  value: 85000,
                  color: DonutPalette.colors[0],
                ),
                DonutSlice(
                  id: 'c2',
                  label: 'Groceries',
                  iconKey: 'groceries',
                  value: 120000,
                  color: DonutPalette.colors[1],
                ),
              ],
              totalMillimes: 205000,
              lang: 'en',
            ),
          ),
        ),
      );
      expect(find.textContaining('205'), findsOneWidget);
    });

    testWidgets('WalletCardView masks hidden balance', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WalletCardView(
              name: 'Cash',
              iconKey: 'cash',
              colorKey: 'teal',
              design: 'classic',
              balanceMillimes: 579500,
              masked: true,
              lang: 'en',
              hidden: true,
            ),
          ),
        ),
      );
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.textContaining('579'), findsNothing);
    });

    testWidgets('WalletCardView dark mode builds', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: WalletCardView(
              name: 'Bank',
              iconKey: 'bank',
              colorKey: 'blue',
              design: 'modern',
              balanceMillimes: 1250000,
              masked: false,
              lang: 'fr',
              hidden: false,
            ),
          ),
        ),
      );
      expect(find.text('BANK'), findsOneWidget);
    });

    testWidgets('MasroufiNavBar: wallets + add + mizania', (t) async {
      var tapped = '';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MasroufiNavBar(
              selected: null,
              lang: 'en',
              onWallets: () => tapped = 'wallets',
              onMizania: () => tapped = 'mizania',
              onAdd: () => tapped = 'add',
            ),
          ),
        ),
      );
      expect(find.text('Wallets'), findsOneWidget);
      expect(find.text('Mizania'), findsOneWidget);
      await t.tap(find.text('Wallets'));
      expect(tapped, 'wallets');
      await t.tap(find.byIcon(Icons.add));
      expect(tapped, 'add');
    });

    testWidgets('HomeTitle tap escapes Wallets back to home', (t) async {
      final router = GoRouter(
        initialLocation: '/wallets',
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/wallets',
            builder: (c, s) => const Scaffold(
              body: HomeTitle(text: 'WALLETS', lang: 'en'),
            ),
          ),
        ],
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      expect(find.text('WALLETS'), findsOneWidget);
      expect(find.byTooltip('Go to home'), findsOneWidget);
      await t.tap(find.text('WALLETS'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    test('shouldInterceptBack traps only wallets/mizania branches', () {
      expect(shouldInterceptBack(0), isFalse); // transactions
      expect(shouldInterceptBack(1), isFalse); // dashboard
      expect(shouldInterceptBack(2), isTrue); // wallets
      expect(shouldInterceptBack(3), isTrue); // mizania
    });

    testWidgets('MasroufiNavBar Arabic RTL labels', (t) async {
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              bottomNavigationBar: MasroufiNavBar(
                selected: 'wallets',
                lang: 'ar',
                onWallets: () {},
                onMizania: () {},
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('المحافظ'), findsOneWidget);
      expect(find.text('ميزانية'), findsOneWidget);
    });
  });
}
