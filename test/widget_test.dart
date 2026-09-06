import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/core/money/money.dart';
import 'package:masroufi/core/widgets/widgets.dart';

void main() {
  testWidgets('empty state renders localized strings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Scaffold(
          body: EmptyState(
            title: Strings.get('ar', 'noTransactions'),
            body: Strings.get('ar', 'noTransactionsBody'),
            icon: Icons.receipt_long,
          ),
        ),
      ),
    );
    expect(find.text('لا توجد عمليات بعد'), findsOneWidget);
  });

  testWidgets('TND amount displays with suffix', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Text(Money.format(87500, lang: 'ar'))),
      ),
    );
    expect(find.textContaining('د.ت'), findsOneWidget);
    expect(find.textContaining('87.500'), findsOneWidget);
  });

  testWidgets('RTL directionality for Arabic', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('fr'), Locale('ar')],
        home: Scaffold(body: Text('x')),
      ),
    );
    final ctx = tester.element(find.text('x'));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });
}
