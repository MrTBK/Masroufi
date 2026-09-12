import 'periods.dart';

/// Daily budget guidance (deterministic, documented, int-only):
/// remaining budget spread over the days left in the month INCLUDING
/// today. `daysLeft` is clamped to [1, daysInMonth] so the division is
/// total. A negative `remaining` (over budget) yields a negative
/// `suggested`: callers show the over-budget state, never a target.
({int remaining, int daysLeft, int suggested}) dailyGuidance({
  required int budgetMillimes,
  required int spentMillimes,
  required DateTime now,
}) {
  final daysInMonth = Periods.daysInMonth(now.year, now.month);
  final daysLeft = (daysInMonth - now.day + 1).clamp(1, daysInMonth);
  final remaining = budgetMillimes - spentMillimes;
  return (
    remaining: remaining,
    daysLeft: daysLeft,
    suggested: remaining ~/ daysLeft,
  );
}
