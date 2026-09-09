/// Pure financial-period bounds in local time (unit-testable).
/// All ranges are half-open [start, end). No floats, no widgets.
abstract final class Periods {
  /// Start of the calendar day containing [dt].
  static DateTime dayStart(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static ({DateTime start, DateTime end}) day(DateTime now) {
    final s = dayStart(now);
    return (start: s, end: s.add(const Duration(days: 1)));
  }

  static ({DateTime start, DateTime end}) yesterday(DateTime now) {
    final s = dayStart(now).subtract(const Duration(days: 1));
    return (start: s, end: s.add(const Duration(days: 1)));
  }

  /// Week containing [now]. [weekStart] is monday|sunday|saturday
  /// (SettingsRepo.weekStarts); unknown values fall back to Monday.
  static ({DateTime start, DateTime end}) week(
    DateTime now, [
    String weekStart = 'monday',
  ]) {
    final target = switch (weekStart) {
      'sunday' => DateTime.sunday,
      'saturday' => DateTime.saturday,
      _ => DateTime.monday,
    };
    // DateTime.weekday: Monday=1..Sunday=7.
    final back = (dayStart(now).weekday - target + 7) % 7;
    final s = dayStart(now).subtract(Duration(days: back));
    return (start: s, end: s.add(const Duration(days: 7)));
  }

  static ({DateTime start, DateTime end}) month(DateTime now) =>
      (start: DateTime(now.year, now.month, 1), end: _nextMonth(now));

  static DateTime _nextMonth(DateTime dt) => dt.month == 12
      ? DateTime(dt.year + 1, 1, 1)
      : DateTime(dt.year, dt.month + 1, 1);

  static ({DateTime start, DateTime end}) lastMonth(DateTime now) {
    final thisStart = DateTime(now.year, now.month, 1);
    final prevStart = now.month == 1
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, now.month - 1, 1);
    return (start: prevStart, end: thisStart);
  }

  /// Week before the week containing [now] (same [weekStart] convention).
  static ({DateTime start, DateTime end}) lastWeek(
    DateTime now, [
    String weekStart = 'monday',
  ]) {
    final cur = week(now, weekStart);
    final s = cur.start.subtract(const Duration(days: 7));
    return (start: s, end: s.add(const Duration(days: 7)));
  }

  /// Transaction-timeline periods for the redesigned home experience.
  /// Ids: today|yesterday|thisWeek|lastWeek|thisMonth|lastMonth.
  /// All ranges half-open [start, end), local time.
  static ({DateTime start, DateTime end}) txnRangeFor(
    String period,
    DateTime now,
    String weekStart,
  ) {
    switch (period) {
      case 'today':
        return day(now);
      case 'yesterday':
        return yesterday(now);
      case 'thisWeek':
        return week(now, weekStart);
      case 'lastWeek':
        return lastWeek(now, weekStart);
      case 'lastMonth':
        return lastMonth(now);
      case 'thisMonth':
      default:
        return month(now);
    }
  }

  /// Whole elapsed days in [start, end) clamped to >= 1.
  /// Used for daily-average definitions (never divide by zero).
  static int elapsedDays(DateTime start, DateTime end, DateTime now) {
    final effectiveEnd = now.isBefore(end)
        ? dayStart(now).add(const Duration(days: 1))
        : end;
    final days = effectiveEnd.difference(dayStart(start)).inDays;
    return days < 1 ? 1 : days;
  }

  static ({DateTime start, DateTime end}) year(DateTime now) =>
      (start: DateTime(now.year, 1, 1), end: DateTime(now.year + 1, 1, 1));

  /// Last 3 calendar months including the month containing [now]:
  /// [start] is the first day of (month - 2), [end] the first day of the
  /// next month. Half-open [start, end).
  static ({DateTime start, DateTime end}) last3Months(DateTime now) {
    var y = now.year;
    var m = now.month - 2;
    while (m < 1) {
      m += 12;
      y--;
    }
    return (start: DateTime(y, m, 1), end: _nextMonth(now));
  }

  /// Last [n] COMPLETED months before the month containing [now],
  /// oldest first. Current partial month is never included.
  static List<({int year, int month})> lastCompletedMonths(
    DateTime now,
    int n,
  ) {
    final out = <({int year, int month})>[];
    var y = now.year;
    var m = now.month;
    for (var i = 0; i < n; i++) {
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
      out.add((year: y, month: m));
    }
    return out.reversed.toList();
  }

  static int daysInMonth(int year, int month) =>
      _nextMonth(DateTime(year, month, 1))
          .subtract(const Duration(days: 1))
          .day;
}
