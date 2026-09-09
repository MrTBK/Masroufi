import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/notify/notify_planner.dart';

/// Deterministic planner tests (§33): same snapshot → same plan.
/// Delivery (`AppNotifier`) is untestable hardware and stays untested.
void main() {
  final now = DateTime(2026, 9, 8, 10, 0);

  List<PlannedNotification> plan({
    BudgetInput? overall,
    List<BudgetInput> categories = const [],
    List<RecurringInput> due = const [],
    int spent = 0,
    int avg = 10000,
  }) => NotificationPlanner.plan(
    lang: 'en',
    now: now,
    overall: overall,
    categories: categories,
    dueTomorrow: due,
    todaySpentMillimes: spent,
    dailyAverageMillimes: avg,
  );

  group('NotificationPlanner', () {
    test('empty snapshot plans nothing', () {
      expect(plan(), isEmpty);
    });

    test('overall exceeded vs 80% warning vs quiet', () {
      final over = plan(
        overall: const BudgetInput(amountMillimes: 1000, spentMillimes: 1200),
      );
      expect(over, hasLength(1));
      expect(over.single.id, 100);
      expect(over.single.title, 'Monthly budget exceeded');

      final warn = plan(
        overall: const BudgetInput(amountMillimes: 1000, spentMillimes: 850),
      );
      expect(warn.single.title, 'Budget 85% used');

      expect(
        plan(
          overall: const BudgetInput(amountMillimes: 1000, spentMillimes: 500),
        ),
        isEmpty,
      );
    });

    test('zero/negative budgets never divide or alert', () {
      expect(
        plan(
          overall: const BudgetInput(amountMillimes: 0, spentMillimes: 500),
        ),
        isEmpty,
      );
    });

    test('category lines capped at top-3 pct, stable ids', () {
      BudgetInput cat(String n, int spent) => BudgetInput(
        categoryName: n,
        amountMillimes: 1000,
        spentMillimes: spent,
      );
      final lines = plan(
        categories: [
          cat('a', 810),
          cat('b', 820),
          cat('c', 830),
          cat('d', 840),
          cat('e', 500), // below 80%: silent
        ],
      );
      expect(lines, hasLength(3));
      expect(lines.map((l) => l.id), [200, 201, 202]);
      expect(lines.first.title, contains('d'));
    });

    test('recurring reminders capped at 5, stable ids', () {
      final lines = plan(
        due: [
          for (var i = 0; i < 7; i++)
            RecurringInput(name: 'r$i', amountMillimes: 1000),
        ],
      );
      expect(lines, hasLength(5));
      expect(lines.first.id, 300);
      expect(lines.first.title, contains('r0'));
      expect(lines.first.title, contains('tomorrow'));
    });

    test('high-spending nudge needs avg>0 and >2x', () {
      expect(plan(spent: 30000, avg: 10000).map((l) => l.id), contains(400));
      expect(plan(spent: 20000, avg: 10000), isEmpty); // exactly 2x: quiet
      expect(plan(spent: 999999, avg: 0), isEmpty); // no average: quiet
    });

    test('digest slot is next 20:00 local', () {
      final lines = plan(
        overall: const BudgetInput(amountMillimes: 1000, spentMillimes: 1000),
      );
      expect(lines.single.when, DateTime(2026, 9, 8, 20));
      final late = NotificationPlanner.plan(
        lang: 'en',
        now: DateTime(2026, 9, 8, 21, 0),
        todaySpentMillimes: 0,
        dailyAverageMillimes: 0,
        overall: const BudgetInput(amountMillimes: 1000, spentMillimes: 1000),
      );
      expect(late.single.when, DateTime(2026, 9, 9, 20));
    });
  });
}
