/// Pure recurring-date math (unit-testable). All int/DateTime, no floats.
/// Frequencies: daily | weekly | monthly | yearly.
abstract final class Recurring {
  static const List<String> frequencies = [
    'daily',
    'weekly',
    'monthly',
    'yearly',
  ];

  static int daysInMonth(int year, int month) {
    final next = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  /// Next occurrence strictly after [date], clamping month-ends
  /// (Jan 31 -> Feb 28/29) and Feb 29 -> Feb 28 on non-leap years.
  /// Time-of-day is preserved from [date].
  static DateTime nextAfter(DateTime date, String frequency) {
    switch (frequency) {
      case 'daily':
        return date.add(const Duration(days: 1));
      case 'weekly':
        return date.add(const Duration(days: 7));
      case 'monthly':
        var y = date.year;
        var m = date.month + 1;
        if (m > 12) {
          m = 1;
          y++;
        }
        final d = date.day.clamp(1, daysInMonth(y, m));
        return DateTime(y, m, d, date.hour, date.minute);
      case 'yearly':
        final y = date.year + 1;
        final d = date.day.clamp(1, daysInMonth(y, date.month));
        return DateTime(y, date.month, d, date.hour, date.minute);
      default:
        throw ArgumentError('unknown frequency $frequency');
    }
  }

  /// All occurrences of a rule within [from]..[to] inclusive,
  /// starting at [start] and stopping at [end] (if set).
  static List<DateTime> occurrencesBetween({
    required DateTime start,
    required String frequency,
    required DateTime from,
    required DateTime to,
    DateTime? end,
    int limit = 366,
  }) {
    final out = <DateTime>[];
    var cur = start;
    // Fast-forward to the window.
    var guard = 0;
    while (cur.isBefore(from) && guard++ < 5000) {
      cur = nextAfter(cur, frequency);
    }
    guard = 0;
    while (!cur.isAfter(to) && out.length < limit && guard++ < 5000) {
      if (end != null && cur.isAfter(end)) break;
      out.add(cur);
      cur = nextAfter(cur, frequency);
    }
    return out;
  }
}
