import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/budgets/budget_intel.dart';
import 'package:masroufi/core/notify/notify_planner.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/category_budgets_repo.dart';

AppDb _db() => AppDb.forTesting(NativeDatabase.memory());

void main() {
  group('BudgetIntel.projectionAlert', () {
    test('fires when pace exceeds budget', () {
      // 15th of 30-day month, 600 spent → daily 40 → projected 1200 > 1000.
      final p = BudgetIntel.projectionAlert(
        spentSoFar: 600000,
        now: DateTime(2026, 9, 15),
        budgetMillimes: 1000000,
      );
      expect(p, 1200000);
    });

    test('quiet when under pace', () {
      final p = BudgetIntel.projectionAlert(
        spentSoFar: 100000,
        now: DateTime(2026, 9, 15),
        budgetMillimes: 1000000,
      );
      expect(p, isNull);
    });

    test('month boundaries: Jan 31, Feb leap', () {
      // Feb 2026 has 28 days; day 28 spent 280 → projected 280.
      final feb = BudgetIntel.projectionAlert(
        spentSoFar: 280000,
        now: DateTime(2026, 2, 28),
        budgetMillimes: 200000,
      );
      expect(feb, 280000);
      // Jan 1: elapsed 1, spent 50000, 31 days → 1550000.
      final jan = BudgetIntel.projectionAlert(
        spentSoFar: 50000,
        now: DateTime(2026, 1, 1),
        budgetMillimes: 1000000,
      );
      expect(jan, 1550000);
      // Dec→Jan prevMonth helper.
      expect(BudgetIntel.prevMonth(DateTime(2026, 1, 15)), (
        year: 2025,
        month: 12,
      ));
      expect(BudgetIntel.prevMonth(DateTime(2026, 9, 9)), (
        year: 2026,
        month: 8,
      ));
    });
  });

  group('BudgetIntel.effectiveBudget (rollover display-only)', () {
    test('off returns current', () {
      expect(
        BudgetIntel.effectiveBudget(
          currentBudgetMillimes: 1000,
          prevBudgetMillimes: 800,
          prevSpentMillimes: 500,
          rolloverEnabled: false,
        ),
        1000,
      );
    });

    test('on adds leftover, clamps over-spend', () {
      expect(
        BudgetIntel.effectiveBudget(
          currentBudgetMillimes: 1000,
          prevBudgetMillimes: 800,
          prevSpentMillimes: 500,
          rolloverEnabled: true,
        ),
        1300,
      );
      expect(
        BudgetIntel.effectiveBudget(
          currentBudgetMillimes: 1000,
          prevBudgetMillimes: 800,
          prevSpentMillimes: 900,
          rolloverEnabled: true,
        ),
        1000,
      );
    });
  });

  group('copy-last-month idempotent', () {
    test('overall + categories copy once, never overwrite', () async {
      final db = _db();
      final budgets = BudgetsRepo(db);
      final cats = CategoryBudgetsRepo(db);
      await budgets.upsert(2026, 8, 500000);
      await cats.upsert('c1', 2026, 8, 100000);
      // First copy → true/1.
      expect(await budgets.copyFromPrev(2026, 9), isTrue);
      expect(await cats.copyFromPrev(2026, 9), 1);
      // Second copy → false/0 (idempotent, no overwrite).
      expect(await budgets.copyFromPrev(2026, 9), isFalse);
      expect(await cats.copyFromPrev(2026, 9), 0);
      // Change target, copy must not overwrite.
      await budgets.upsert(2026, 9, 999000);
      expect((await budgets.getMonth(2026, 9))!.amountMillimes, 999000);
      // Jan boundary: Dec 2025 → Jan 2026.
      await budgets.upsert(2025, 12, 111000);
      expect(await budgets.copyFromPrev(2026, 1), isTrue);
      expect((await budgets.getMonth(2026, 1))!.amountMillimes, 111000);
      await db.close();
    });
  });

  group('planner projection rule', () {
    test('adds pace alert id 150 when projected over', () {
      final plan = NotificationPlanner.plan(
        lang: 'en',
        now: DateTime(2026, 9, 15, 10),
        todaySpentMillimes: 0,
        dailyAverageMillimes: 0,
        projectionSpent: 600000,
        projectionBudget: 1000000,
        projectionElapsed: 15,
        projectionDays: 30,
      );
      expect(plan.any((n) => n.id == 150), isTrue);
      final quiet = NotificationPlanner.plan(
        lang: 'en',
        now: DateTime(2026, 9, 15, 10),
        todaySpentMillimes: 0,
        dailyAverageMillimes: 0,
        projectionSpent: 100000,
        projectionBudget: 1000000,
        projectionElapsed: 15,
        projectionDays: 30,
      );
      expect(quiet.any((n) => n.id == 150), isFalse);
    });
  });
}
