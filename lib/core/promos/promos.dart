/// Static promo inventory: unofficial ads with no SDK and no tracking.
///
/// Promos ship inside the app, so they are offline-safe, make zero
/// network calls, and need zero new permissions. Paid placements get
/// appended to [Promos.all] per release; an empty registry means the
/// donate page shows the house invite card instead.
final class Promo {
  const Promo({
    required this.id,
    required this.titleKey,
    required this.bodyKey,
    required this.link,
    required this.start,
    required this.end,
  });

  final String id;
  final String titleKey;
  final String bodyKey;
  final String link;
  final DateTime start;
  final DateTime end;
}

abstract final class Promos {
  /// Paid inventory. Empty until the first placement is sold.
  static const List<Promo> all = [];

  /// Promos live on [now] (inclusive bounds), stable id order.
  static List<Promo> activeOn(DateTime now, {List<Promo>? pool}) {
    final list =
        (pool ?? all)
            .where((p) => !now.isBefore(p.start) && !now.isAfter(p.end))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// One promo per day: deterministic rotation across active inventory.
  static Promo? pickFor(DateTime now, {List<Promo>? pool}) {
    final active = activeOn(now, pool: pool);
    if (active.isEmpty) return null;
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    return active[dayOfYear % active.length];
  }
}
