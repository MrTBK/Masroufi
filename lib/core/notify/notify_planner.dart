import '../l10n/strings.dart';
import '../money/money.dart';

/// Deterministic local-notification planner (brief §33).
///
/// Pure: same ledger snapshot → same plan, no I/O, no clocks except the
/// injected [now]. The thin `AppNotifier` only delivers what this
/// returns. All math int-only; all text via localized templates.
///
/// Rules (digest scheduled for the next 20:00 local):
/// - overall budget: spent ≥ amount → exceeded; ≥ 80% → warning.
/// - per-category budgets: same, capped to the 3 highest pcts.
/// - recurring due tomorrow: one reminder each (capped at 5).
/// - today-vs-average: todaySpent > 2 × dailyAverage (avg > 0) → nudge.
class PlannedNotification {
  /// Stable id for cancel/replace semantics (100 overall, 200+i cats,
  /// 300+i recurring, 400 nudge).
  final int id;
  final String title;
  final String body;
  final DateTime when;
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });
}

class BudgetInput {
  final String? categoryName;
  final int amountMillimes;
  final int spentMillimes;
  const BudgetInput({
    this.categoryName,
    required this.amountMillimes,
    required this.spentMillimes,
  });
}

class RecurringInput {
  final String name;
  final int amountMillimes;
  const RecurringInput({required this.name, required this.amountMillimes});
}

abstract final class NotificationPlanner {
  static List<PlannedNotification> plan({
    required String lang,
    required DateTime now,
    BudgetInput? overall,
    List<BudgetInput> categories = const [],
    List<RecurringInput> dueTomorrow = const [],
    required int todaySpentMillimes,
    required int dailyAverageMillimes,
  }) {
    final out = <PlannedNotification>[];
    // Next 20:00 local digest slot (today if still ahead, else tomorrow).
    var slot = DateTime(now.year, now.month, now.day, 20);
    if (!slot.isAfter(now)) slot = slot.add(const Duration(days: 1));

    void budgetLine(BudgetInput b, int id, bool isOverall) {
      if (b.amountMillimes <= 0 || b.spentMillimes < 0) return;
      final pct = (b.spentMillimes * 100) ~/ b.amountMillimes;
      if (pct >= 100) {
        out.add(
          PlannedNotification(
            id: id,
            title: isOverall
                ? Strings.get(lang, 'notifBudgetExceeded')
                : Strings.tpl(lang, 'notifCatExceeded', {
                    'cat': b.categoryName ?? '',
                  }),
            body: Money.inline(b.spentMillimes, lang: lang),
            when: slot,
          ),
        );
      } else if (pct >= 80) {
        out.add(
          PlannedNotification(
            id: id,
            title: Strings.tpl(
              lang,
              isOverall ? 'notifBudgetWarning' : 'notifCatWarning',
              {'cat': b.categoryName ?? '', 'p': '$pct'},
            ),
            body: '$pct%',
            when: slot,
          ),
        );
      }
    }

    if (overall != null) budgetLine(overall, 100, true);
    final ranked = categories
        .where((b) => b.amountMillimes > 0 && b.spentMillimes * 100 >= 80 * b.amountMillimes)
        .toList()
      ..sort(
        (a, b) => (b.spentMillimes * 100 ~/ b.amountMillimes).compareTo(
          a.spentMillimes * 100 ~/ a.amountMillimes,
        ),
      );
    for (var i = 0; i < ranked.length && i < 3; i++) {
      budgetLine(ranked[i], 200 + i, false);
    }
    for (var i = 0; i < dueTomorrow.length && i < 5; i++) {
      final r = dueTomorrow[i];
      out.add(
        PlannedNotification(
          id: 300 + i,
          title: Strings.tpl(lang, 'notifRecurringDue', {'name': r.name}),
          body: Money.inline(r.amountMillimes, lang: lang),
          when: slot,
        ),
      );
    }
    if (dailyAverageMillimes > 0 &&
        todaySpentMillimes > 2 * dailyAverageMillimes) {
      out.add(
        PlannedNotification(
          id: 400,
          title: Strings.get(lang, 'notifHighSpending'),
          body: Money.inline(todaySpentMillimes, lang: lang),
          when: slot,
        ),
      );
    }
    return out;
  }
}
