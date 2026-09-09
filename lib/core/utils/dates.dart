import '../l10n/strings.dart';
// Hide intl's own TextDirection class (shadows Flutter's enum).
import 'package:intl/intl.dart' hide TextDirection;

/// Relative-day labels for timelines ("Today", "Yesterday", else M/D).
/// Pure function: pass the UI language explicitly (testable, no context).
String relativeDay(DateTime dt, DateTime now, String lang) {
  final day = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return Strings.get(lang, 'today');
  if (diff == 1) return Strings.get(lang, 'yesterday');
  return '${dt.month}/${dt.day}';
}

/// Section header for a timeline day group: the dedicated "today"
/// label for the current day, locale-aware weekday headers otherwise.
/// Pure + unit-tested (RTL-safe: no manual direction fiddling).
/// Shared by the Transactions timeline and the dashboard calendar sheet.
String dayGroupHeader(DateTime day, DateTime now, String lang) {
  if (DateTime(day.year, day.month, day.day) ==
      DateTime(now.year, now.month, now.day)) {
    return Strings.get(lang, 'todayTransactions');
  }
  final rel = relativeDay(day, now, lang);
  if (rel == Strings.get(lang, 'yesterday')) return rel.toUpperCase();
  try {
    final locale = switch (lang) {
      'ar' => 'ar',
      'fr' => 'fr',
      _ => 'en',
    };
    return DateFormat('EEEE, MMMM d', locale).format(day).toUpperCase();
  } catch (_) {
    return rel.toUpperCase();
  }
}

/// Month section header key, e.g. "2026-09".
String monthKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
