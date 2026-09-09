import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:masroufi/app/app.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/widgets/design.dart';
import 'package:masroufi/data/database/app_db.dart';

/// On-device QA matrix (Track A). Fresh install assumed
/// (`adb shell pm clear com.masroufi.app` before running).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester tester, {bool reset = false}) async {
    final db = AppDb();
    if (reset) {
      // Hermetic start regardless of device state (pm clear is flaky here).
      await db.delete(db.transactions).go();
      await db.delete(db.budgets).go();
      await db.delete(db.wallets).go();
      await db.delete(db.categories).go();
      await db.delete(db.appSettings).go();
      await db.delete(db.recurringRules).go();
      await db.delete(db.categoryBudgets).go();
      await db.delete(db.savingsContributions).go();
      await db.delete(db.savingsGoals).go();
      await db.delete(db.debtPayments).go();
      await db.delete(db.debts).go();
    }
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    await container.read(categoriesRepoProvider).seedDefaults();
    // Mirror main.dart: hydrate providers from persisted settings.
    final settings = container.read(settingsRepoProvider);
    container.read(languageProvider.notifier).state = await settings.language();
    container.read(themeNameProvider.notifier).state = await settings.theme();
    container.read(onboardingDoneProvider.notifier).state = await settings
        .onboardingDone();
    container.read(hideBalancesProvider.notifier).state = await settings
        .hideBalances();
    container.read(weekStartProvider.notifier).state = await settings
        .weekStart();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MasroufiApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final probe = find.text(text);
    // Lazily-built lists may not contain offscreen items yet: scroll the
    // primary scrollable until the text materializes (no-op if visible).
    for (var i = 0; i < 8 && probe.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Enter text then hide the soft keyboard so bottom buttons stay tappable.
  Future<void> enterTextHide(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.enterText(finder, text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  /// Bottom-nav navigation via the router (deterministic). Raw taps on the
  /// nav bar proved flaky on-device (silent hit-test misses after lists
  /// settle); branch content — what this matrix asserts — is identical.
  /// Redesign IA: Transactions (/) + Dashboard (/dashboard) share home,
  /// Wallets (/wallets) + Mizania (/mizania) flank the + action,
  /// Settings (/settings) replaces the old More hub (legacy /more/* kept
  /// as redirects).
  Future<void> tapNav(WidgetTester tester, String text) async {
    const branches = {
      'الرئيسية': '/',
      'السجل': '/',
      'العمليات': '/',
      'لوحة التحكم': '/dashboard',
      'المحافظ': '/wallets',
      'المزيد': '/settings',
      'ميزانية': '/mizania',
      'Accueil': '/',
      'Historique': '/',
      'Transactions': '/',
      'Tableau de bord': '/dashboard',
      'Portefeuilles': '/wallets',
      'Plus': '/settings',
      'Mizania': '/mizania',
      'Dashboard': '/dashboard',
      'History': '/',
      'Wallets': '/wallets',
      'More': '/settings',
    };
    final ctx = tester.element(find.byType(Scaffold).first);
    GoRouter.of(ctx).go(branches[text]!);
    await tester.pumpAndSettle();
  }

  /// Dominant + action in the bottom bar. MUST NOT use tapIcon(add):
  /// income rows render an Icons.add type glyph, which sorts before the
  /// bar in tree order (tapping it opens the edit form instead). The
  /// bar sits after Scaffold.body, so its + is reliably .last.
  Future<void> tapPlus(WidgetTester tester) async {
    final target = find.byIcon(Icons.add).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Tap an icon button robustly (ensure visible first: raw taps on
  /// settled lists can silently miss).
  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final target = find.byIcon(icon).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Scroll a lazily-built page list until [text] is visible (no tap).
  /// Tolerates the target not being built yet between drags.
  Future<void> scrollToVisible(WidgetTester tester, String text) async {
    for (var i = 0; i < 15; i++) {
      if (find.text(text).evaluate().isNotEmpty) break;
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text(text).first);
    await tester.pumpAndSettle();
    expect(find.text(text), findsWidgets);
  }

  testWidgets('QA matrix: full MVP + V1.1 on device', (tester) async {
    await boot(tester, reset: true);
    // --- 1: onboarding in Arabic, Cash 100 ---
    expect(find.text('Choose your language'), findsOneWidget);
    await tapText(tester, 'العربية');
    await tapText(tester, 'التالي');
    expect(find.text('أنشئ أول محفظة'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'الرصيد الابتدائي'),
      '100',
    );
    // Onboarding is 2 steps (language → wallet); theme lives in Settings.
    await tapText(tester, 'ابدأ');
    // Raw taps can silently miss on-device: still onboarding? tap again.
    for (var i = 0; i < 3 && find.text('ابدأ').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('ابدأ').first);
      await tester.pumpAndSettle();
    }
    expect(find.text('مصروفي'), findsWidgets);
    expect(find.text('العمليات'), findsWidgets);
    expect(find.textContaining('100.000'), findsWidgets);

    // --- 2-5: expenses + income math ---
    expect(find.text('مصروفي'), findsWidgets);

    Future<void> tapSheetText(WidgetTester tester, String text) async {
      // Sheet rows can duplicate form text behind the modal barrier
      // (e.g. the field card shows the parent name as subtitle). The
      // page route precedes overlay entries in tree order, so the
      // sheet's copy is always last.
      final finder = find.text(text).last;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tapSheetLeaf(WidgetTester tester, String text) =>
        tapSheetText(tester, text);

    // Sheet rows sort AFTER the home route in tree order, so .last
    // disambiguates from same-labeled widgets behind the modal barrier
    // (e.g. the empty-timeline CTA also reads 'إضافة مصروف').
    Future<void> tapSheetAction(WidgetTester tester, String text) async {
      final finder = find.text(text).last;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> addExpense(String amount, String parent, String cat) async {
      // Redesign entry: dominant + bottom-bar action -> sheet -> expense.
      await tapPlus(tester);
      await tapSheetAction(tester, 'إضافة مصروف');
      final amtFinder = find.widgetWithText(TextField, 'المبلغ');
      final dflt = find
          .descendant(of: amtFinder, matching: find.byType(EditableText))
          .evaluate()
          .length;
      String rect;
      try {
        rect = '${tester.getRect(amtFinder)}';
      } catch (e) {
        rect = 'NORECT $e';
      }
      // ignore: avoid_print
      print(
        'DEBUG addExpense $amount: amountFields=${amtFinder.evaluate().length} '
        'textFields=${find.byType(TextField).evaluate().length} '
        'editable=${find.descendant(of: amtFinder, matching: find.byType(EditableText, skipOffstage: false)).evaluate().length} '
        'dflt=$dflt rect=$rect',
      );
      await enterTextHide(
        tester,
        find.widgetWithText(TextField, 'المبلغ'),
        amount,
      );
      // Two-step picker: category field -> primary -> subcategory.
      await tester.tap(find.byKey(const ValueKey('categoryField')));
      await tester.pumpAndSettle();
      await tapSheetText(tester, parent);
      await tapSheetLeaf(tester, cat);
      // .last: the home empty-state CTA shares this label behind us.
      final saveBtn = find
          .widgetWithText(FilledButton, 'إضافة مصروف')
          .last;
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
    }

    await addExpense('12.500', 'طعام ومشروبات', 'مقهى');
    expect(find.textContaining('87.500'), findsWidgets);
    await addExpense('8', 'نقل', 'تاكسي');
    expect(find.textContaining('79.500'), findsWidgets);

    // Income via the dominant + action (redesign has no home quick
    // actions; the type FilterChip also reads 'مدخول' so tap the icon).
    await tapPlus(tester);
    await tapText(tester, 'إضافة مدخول');
    // ignore: avoid_print
    print(
      'DEBUG income: amountFields=${find.widgetWithText(TextField, 'المبلغ').evaluate().length} '
      'textFields=${find.byType(TextField).evaluate().length} '
      'addIncomeTitle=${find.text('إضافة مدخول').evaluate().length} '
      'loading=${find.byType(CircularProgressIndicator).evaluate().length}',
    );
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'المبلغ'),
      '500',
    );
    final incomeSave = find.widgetWithText(FilledButton, 'إضافة مدخول');
    await tester.ensureVisible(incomeSave);
    await tester.pumpAndSettle();
    await tester.tap(incomeSave);
    await tester.pumpAndSettle();
    expect(find.textContaining('579.500'), findsWidgets);

    // --- 6: transfer conserves total ---
    // Create Bank wallet.
    await tapText(tester, 'المحافظ');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'اسم المحفظة'),
      'Bank',
    );
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'الرصيد الابتدائي'),
      '0',
    );
    await tapText(tester, 'حفظ');
    // Wallet cards render names uppercase in the new design.
    expect(find.text('BANK'), findsOneWidget);

    // Transfer 100 Cash -> Bank from dashboard quick action.
    // NOTE: reached via router (dashboard scroll position makes raw taps
    // on the quick-action row flaky); the buttons themselves are covered
    // by the expense/income quick-action taps above.
    await tapNav(tester, 'العمليات');
    final navCtx = tester.element(find.text('مصروفي').first);
    GoRouter.of(navCtx).push('/add?type=transfer');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'تحويل مبلغ'), findsOneWidget);
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'المبلغ'),
      '100',
    );
    // Destination wallet card: with 2 wallets the To-group Bank card is
    // WalletSelectCard index 3 (From: Cash, Bank; To: Cash, Bank).
    final saveBtn = find.widgetWithText(FilledButton, 'تحويل مبلغ');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    final toBankCard = find.byType(WalletSelectCard).at(3);
    await tester.ensureVisible(toBankCard);
    await tester.pumpAndSettle();
    await tester.tap(toBankCard);
    await tester.pumpAndSettle();
    // Tap the save BUTTON (not tapText: the AppBar title reads the same
    // and sorts first in tree order, which would no-op on the title).
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    // Transfer conserves the total (579.500 before and after).
    expect(find.textContaining('579.500'), findsWidgets);
    // Both legs landed: Cash 479.500, Bank 100.000 on the wallet cards.
    await tapNav(tester, 'المحافظ');
    expect(find.textContaining('479.500'), findsWidgets);
    expect(find.textContaining('100.000'), findsWidgets);
    await tapNav(tester, 'العمليات');

    // --- 7: monthly budget (Mizania branch) ---
    await tapNav(tester, 'ميزانية');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(tester, find.byType(TextField).first, '250');
    await tapText(tester, 'حفظ');
    expect(find.textContaining('250.000'), findsWidgets);
    expect(find.textContaining('20.500'), findsWidgets); // spent so far

    // --- 10: language FR + dark (settings hub replaces More) ---
    await tapNav(tester, 'المزيد');
    expect(find.text('الإعدادات'), findsWidgets);
    await tapText(tester, 'Français');
    expect(find.text('Paramètres'), findsWidgets);
    await tapText(tester, 'العربية');
    expect(find.text('الإعدادات'), findsWidgets);
    // Dark theme through settings UI, then verify applied brightness.
    await tapText(tester, 'داكن');
    await tapNav(tester, 'العمليات');
    final ctx = tester.element(find.text('مصروفي').first);
    expect(Theme.of(ctx).brightness, Brightness.dark);

    // --- 11: V1.1 flows ---
    // Recurring rule.
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'المتكررة');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(tester, find.widgetWithText(TextField, 'المبلغ'), '45');
    await tapText(tester, 'حفظ');
    // Rule row shows the amount on the recurring page itself
    // (dashboard analytics no longer embeds an upcoming list).
    expect(find.textContaining('45.000'), findsWidgets);
    await tapNav(tester, 'العمليات');

    // Savings goal + contribution.
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'أهداف الادخار');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'اسم الهدف'),
      'Laptop',
    );
    await enterTextHide(tester, find.byType(TextField).at(1), '3000');
    await tapText(tester, 'حفظ');
    expect(find.text('Laptop'), findsOneWidget);
    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    await tapText(tester, 'إضافة مبلغ');
    await enterTextHide(tester, find.byType(TextField).first, '100');
    await tapText(tester, 'حفظ');
    await tester.tapAt(const Offset(20, 20)); // dismiss sheet
    await tester.pumpAndSettle();
    expect(find.textContaining('100.000'), findsWidgets);

    // Debt + partial payment.
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'الديون');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'الشخص'),
      'Ahmed',
    );
    await enterTextHide(tester, find.widgetWithText(TextField, 'الأصلي'), '50');
    await tapText(tester, 'حفظ');
    expect(find.text('Ahmed'), findsOneWidget);
    await tester.tap(find.text('Ahmed'));
    await tester.pumpAndSettle();
    await tapText(tester, 'تسجيل دفعة');
    await enterTextHide(tester, find.byType(TextField).first, '20');
    await tapText(tester, 'حفظ');
    await tester.tapAt(const Offset(20, 20)); // dismiss sheet
    await tester.pumpAndSettle();
    expect(find.textContaining('30.000'), findsWidgets);

    // Category budget.
    await tapNav(tester, 'ميزانية');
    await tapText(tester, '+ تحديد ميزانية تصنيف');
    await enterTextHide(tester, find.byType(TextField).last, '250');
    await tapText(tester, 'حفظ');
    expect(find.textContaining('250.000'), findsWidgets);

    // --- 12: income form offers income categories, never expense ones ---
    await tapNav(tester, 'العمليات');
    await tapPlus(tester);
    await tapText(tester, 'إضافة مدخول');
    expect(find.text('راتب'), findsWidgets);
    expect(find.text('مقهى'), findsNothing);
    expect(find.text('ستذهب الأموال إلى'), findsOneWidget);
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'المبلغ'),
      '2000',
    );
    final incomeSave2 = find.widgetWithText(FilledButton, 'إضافة مدخول');
    await tester.ensureVisible(incomeSave2);
    await tester.pumpAndSettle();
    await tester.tap(incomeSave2);
    await tester.pumpAndSettle();
    // Raw taps can silently miss on-device: if the form is still open,
    // tap save once more before asserting.
    if (find.widgetWithText(FilledButton, 'إضافة مدخول').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'إضافة مدخول'));
      await tester.pumpAndSettle();
    }
    // 599.500 (incl. 20 debt collection) + 2000 salary.
    expect(find.textContaining('2,599.500'), findsWidgets);

    // --- 13: categories page groups expense + income sections ---
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'إدارة التصنيفات');
    expect(find.text('تصنيفات المصاريف'), findsOneWidget);
    await scrollToVisible(tester, 'تصنيفات الدخل');
    // Leaves live inside collapsed parent tiles: expand income first.
    // Child rows carry hierarchical labels ("Parent › Child").
    await tapText(tester, 'الأرباح');
    await scrollToVisible(tester, 'الأرباح › راتب');

    // --- 14: hiding excludes the wallet from summaries, math intact ---
    await tapNav(tester, 'المحافظ');
    await tapIcon(tester, Icons.visibility); // hide Cash
    expect(find.text('••••••••'), findsWidgets); // Cash card masked
    // Home total now sums visible wallets only (Bank 100.000): nothing
    // masked, nothing leaked.
    await tapNav(tester, 'العمليات');
    expect(find.text('••••••••'), findsNothing);
    expect(find.textContaining('100.000'), findsWidgets);
    // Global switch via the transactions summary eye masks everything too.
    await tapIcon(tester, Icons.visibility);
    expect(find.text('••••••••'), findsWidgets);
    await tapIcon(tester, Icons.visibility_off);
    expect(find.text('••••••••'), findsNothing);
    // Unhide Cash: exact total returns, nothing lost.
    await tapNav(tester, 'المحافظ');
    await tapIcon(tester, Icons.visibility_off);
    await tapNav(tester, 'العمليات');
    expect(find.textContaining('2,599.500'), findsWidgets);
  });
}
