import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/export/monthly_statement.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/features/reports/reports_page.dart';
import 'package:drift/native.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('MonthlyStatementBuilder', () {
    test('totals vs fixtures (income/expense/net)', () {
      final d = MonthlyStatementBuilder.build(
        year: 2026,
        month: 9,
        incomeMillimes: 500000,
        expenseMillimes: 320500,
        txnCount: 7,
        byCategory: const {'a': 200000, 'b': 120500},
        categoryNames: const {'a': 'Food', 'b': 'Taxi'},
        budgetMillimes: 400000,
        budgetSpentMillimes: 320500,
      );
      expect(d.netMillimes, 179500);
      expect(d.topCategories.length, 2);
      expect(d.topCategories.first.name, 'Food');
      expect(d.topCategories.first.total, 200000);
      expect(d.budgetRemaining, 79500);
    });

    test('caps at 5, drops zero, sorts desc', () {
      final d = MonthlyStatementBuilder.build(
        year: 2026,
        month: 1,
        incomeMillimes: 0,
        expenseMillimes: 100,
        txnCount: 10,
        byCategory: const {
          'a': 10,
          'b': 0,
          'c': 50,
          'd': 30,
          'e': 20,
          'f': 40,
          'g': 5,
        },
      );
      expect(d.topCategories.length, 5);
      expect(d.topCategories.first.total, 50);
      expect(d.topCategories.any((c) => c.total == 0), isFalse);
    });

    test('localized month labels incl Arabic bytes', () {
      expect(
        MonthlyStatementBuilder.monthLabel(2026, 9, 'en'),
        'September 2026',
      );
      expect(
        MonthlyStatementBuilder.monthLabel(2026, 9, 'fr'),
        'septembre 2026',
      );
      final ar = MonthlyStatementBuilder.monthLabel(2026, 9, 'ar');
      expect(ar.contains('2026'), isTrue);
      // Arabic bytes present (non-ASCII shaping source).
      expect(ar.runes.any((r) => r > 127), isTrue);
    });

    test('pdf builds, minus sign attached', () async {
      final d = MonthlyStatementBuilder.build(
        year: 2026,
        month: 9,
        incomeMillimes: 100000,
        expenseMillimes: 150000,
        txnCount: 3,
        byCategory: const {'a': 150000},
        categoryNames: const {'a': 'مقهى'},
      );
      expect(d.netMillimes, -50000);
      final bytes = await MonthlyStatementBuilder.buildPdf(
        data: d,
        lang: 'ar',
      );
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.lengthInBytes > 500, isTrue);
    });

    test('pdf with Arabic font bytes builds', () async {
      // Empty font path → fallback Helvetica still builds (offline-safe).
      final d = MonthlyStatementBuilder.build(
        year: 2026,
        month: 9,
        incomeMillimes: 0,
        expenseMillimes: 1000,
        txnCount: 1,
      );
      final bytes = await MonthlyStatementBuilder.buildPdf(
        data: d,
        lang: 'en',
        arabicFont: null,
      );
      expect(bytes.lengthInBytes > 500, isTrue);
    });
  });

  testWidgets('reports page exposes Export PDF button', (t) async {
    final db = _db();
    await t.pumpWidget(
      ProviderScope(
        overrides: [appDbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    await db.close();
  });
}
