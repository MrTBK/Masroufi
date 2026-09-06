import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:masroufi/app/app.dart';
import 'package:masroufi/app/providers.dart';
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MasroufiApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
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

  Future<void> tapNav(WidgetTester tester, String text) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(text),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('1: onboarding in Arabic, Cash 100', (tester) async {
    await boot(tester, reset: true);
    expect(find.text('Choose your language'), findsOneWidget);
    await tapText(tester, 'العربية');
    await tapText(tester, 'التالي'); // Next in Arabic
    // Wallet step.
    expect(find.text('أنشئ أول محفظة'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'الرصيد الابتدائي'),
      '100',
    );
    await tapText(tester, 'التالي');
    await tapText(tester, 'ابدأ'); // Get started
    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.textContaining('100.000'), findsWidgets);
  });

  testWidgets('2-5: expenses + income math on dashboard', (tester) async {
    await boot(tester);
    // Dashboard holds state from previous test? No — fresh pump, same device DB.
    // Onboarding done flag persisted, so we land on dashboard directly.
    expect(find.text('الرئيسية'), findsWidgets);

    Future<void> addExpense(String amount, String cat) async {
      await tapText(tester, 'مصروف');
      await enterTextHide(
        tester,
        find.widgetWithText(TextField, 'المبلغ'),
        amount,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(cat).last);
      await tester.pumpAndSettle();
      await tapText(tester, 'حفظ');
    }

    await addExpense('12.500', 'مقهى');
    expect(find.textContaining('87.500'), findsWidgets);
    await addExpense('8', 'تاكسي');
    expect(find.textContaining('79.500'), findsWidgets);

    // Income.
    await tapText(tester, 'مدخول');
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'المبلغ'),
      '500',
    );
    await tapText(tester, 'حفظ');
    expect(find.textContaining('579.500'), findsWidgets);
  });

  testWidgets('6: transfer conserves total', (tester) async {
    await boot(tester);
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
    expect(find.text('Bank'), findsOneWidget);

    // Transfer 100 Cash -> Bank from dashboard quick action.
    await tapNav(tester, 'الرئيسية');
    await tapText(tester, 'تحويل');
    await enterTextHide(
      tester,
      find.widgetWithText(TextField, 'المبلغ'),
      '100',
    );
    // Second dropdown = destination.
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'حفظ');
    expect(find.textContaining('479.500'), findsWidgets);
  });

  testWidgets('7: monthly budget tracks spending', (tester) async {
    await boot(tester);
    await tapText(tester, 'المزيد');
    await tapText(tester, 'ميزانية الشهر');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await enterTextHide(tester, find.byType(TextField).first, '250');
    await tapText(tester, 'حفظ');
    expect(find.textContaining('250.000'), findsWidgets);
    expect(find.textContaining('20.500'), findsWidgets); // spent so far
  });

  testWidgets('10: language switch FR + dark theme on device', (tester) async {
    await boot(tester);
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'الإعدادات');
    await tapText(tester, 'Français');
    expect(find.text('Accueil'), findsWidgets);
    // Language change rebuilds the router at dashboard; navigate back.
    await tapNav(tester, 'Plus');
    await tapText(tester, 'Paramètres');
    await tapText(tester, 'العربية');
    expect(find.text('الرئيسية'), findsWidgets);
    // Dark theme through settings UI, then verify applied brightness.
    await tapNav(tester, 'المزيد');
    await tapText(tester, 'الإعدادات');
    await tapText(tester, 'داكن');
    await tapNav(tester, 'الرئيسية');
    final ctx = tester.element(find.text('الرئيسية').first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });
}
