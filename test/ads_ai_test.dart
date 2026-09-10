import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/ads/ads_service.dart';
import 'package:masroufi/core/ads/pro_service.dart';
import 'package:masroufi/core/ai/ai_summary.dart';
import 'package:masroufi/core/ai/smart_categorize.dart';
import 'package:masroufi/core/analytics/bi_scope.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/analytics_repo.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/category_budgets_repo.dart';
import 'package:masroufi/data/repositories/debts_repo.dart';
import 'package:masroufi/data/repositories/recurring_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('AdsGate', () {
    test('loads only with consent, no PRO, onboarding done', () {
      expect(
        AdsGate.canLoad(consentGiven: true, isPro: false, onboardingDone: true),
        isTrue,
      );
      expect(
        AdsGate.canLoad(
          consentGiven: false,
          isPro: false,
          onboardingDone: true,
        ),
        isFalse,
      );
      expect(
        AdsGate.canLoad(consentGiven: true, isPro: true, onboardingDone: true),
        isFalse,
      );
      expect(
        AdsGate.canLoad(
          consentGiven: true,
          isPro: false,
          onboardingDone: false,
        ),
        isFalse,
      );
    });

    test('interstitial capped at 10 min', () {
      final now = DateTime(2026, 9, 15, 12);
      expect(AdsGate.interstitialDue(null, now), isTrue);
      expect(
        AdsGate.interstitialDue(now.subtract(const Duration(minutes: 5)), now),
        isFalse,
      );
      expect(
        AdsGate.interstitialDue(now.subtract(const Duration(minutes: 11)), now),
        isTrue,
      );
    });
  });

  group('ProService manual codes', () {
    test('bad format rejected when secret empty', () {
      // Default PRO_SECRET is empty in tests → all codes invalid.
      expect(ProService.verifyManualCode('MASR-AB12-CD34', ''), isFalse);
      expect(ProService.verifyManualCode('garbage', 'device'), isFalse);
    });
  });

  group('SmartCategorize', () {
    test('tunisian keywords map, user confirms', () {
      expect(SmartCategorize.suggest('Café ben yedder'), 'cat_cafe');
      expect(SmartCategorize.suggest('STEG facture'), 'cat_steg');
      expect(SmartCategorize.suggest('taxi louage'), isNotNull);
      expect(SmartCategorize.suggest('random thing xyz'), isNull);
      expect(SmartCategorize.suggest(''), isNull);
    });
  });

  group('AiSummaryBuilder redaction', () {
    test('compact json has totals, no notes, anon wallets', () async {
      final db = _db();
      try {
        final cats = CategoriesRepo(db);
        await cats.seedDefaults();
        final wallets = WalletsRepo(db);
        final cash = await wallets.create(name: 'Cash');
        final txns = TransactionsRepo(db);
        await txns.addExpense(
          amountMillimes: 5500,
          walletId: cash,
          note: 'SECRET-NOTE-MUST-NOT-LEAK',
          when: DateTime(2026, 9, 5),
        );
        final bi = FilteredAnalytics(
          analytics: AnalyticsRepo(db),
          wallets: wallets,
          categories: cats,
          recurring: RecurringRepo(db),
          debts: DebtsRepo(db),
          budgets: BudgetsRepo(db),
          catBudgets: CategoryBudgetsRepo(db),
        );
        final s = await bi.load(
          BiFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 1)),
          now: DateTime(2026, 9, 15),
        );
        final json = AiSummaryBuilder.toCompactJson(s, lang: 'en');
        final encoded = AiSummaryBuilder.encode(s, lang: 'en');
        expect(json['expense'], 5500);
        expect(json['notesIncluded'], false);
        // Notes never leave the device.
        expect(encoded.contains('SECRET-NOTE-MUST-NOT-LEAK'), isFalse);
        // Wallet ids anonymized.
        expect(encoded.contains(cash), isFalse);
        expect((json['wallets'] as List).first['w'], 'w1');
        // Forecast present (P1 wiring).
        expect((json['forecast'] as Map)['projected'], s.forecastProjected);
      } finally {
        await db.close();
      }
    });
  });

  group('BiSnapshot P1 fields', () {
    test('netByWallet + forecast present', () async {
      final db = _db();
      try {
        final cats = CategoriesRepo(db);
        await cats.seedDefaults();
        final wallets = WalletsRepo(db);
        final cash = await wallets.create(name: 'Cash');
        final txns = TransactionsRepo(db);
        await txns.addExpense(
          amountMillimes: 10000,
          walletId: cash,
          when: DateTime(2026, 9, 5),
        );
        await txns.addIncome(
          amountMillimes: 50000,
          walletId: cash,
          when: DateTime(2026, 9, 6),
        );
        final bi = FilteredAnalytics(
          analytics: AnalyticsRepo(db),
          wallets: wallets,
          categories: cats,
          recurring: RecurringRepo(db),
          debts: DebtsRepo(db),
          budgets: BudgetsRepo(db),
          catBudgets: CategoryBudgetsRepo(db),
        );
        final s = await bi.load(
          BiFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 1)),
          now: DateTime(2026, 9, 15),
        );
        expect(s.netByWallet[cash], 40000);
        expect(s.forecastProjected, greaterThan(0));
        expect(s.forecastPacePct, greaterThanOrEqualTo(0));
      } finally {
        await db.close();
      }
    });
  });
}
