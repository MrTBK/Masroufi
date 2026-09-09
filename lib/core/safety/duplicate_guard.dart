import 'package:drift/drift.dart';

import '../../data/database/app_db.dart';

/// Duplicate-expense warning (Track 5, warn-only, no schema).
///
/// Same wallet + same category + same amount within 30 minutes is very
/// often a double-tap. The UI warns but never blocks: the user confirms
/// and the transaction still saves.
abstract final class DuplicateGuard {
  static const window = Duration(minutes: 30);

  /// Pure: does [occurredAt] fall inside the warning window ending at [now]?
  static bool inWindow(DateTime occurredAt, DateTime now) {
    final diff = now.difference(occurredAt);
    return !diff.isNegative && diff <= window;
  }

  /// Scans recent expense/income rows for a same-wallet+category+amount
  /// hit inside [window]. Transfers excluded (two-wallet semantics).
  /// Returns the first hit or null. Warn-only; caller decides.
  static Future<Transaction?> findRecent({
    required AppDb db,
    required String type,
    required int amountMillimes,
    required String walletId,
    required String? categoryId,
    required DateTime now,
  }) async {
    if (type != 'expense' && type != 'income') return null;
    final since = now.subtract(window);
    final rows =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.type.equals(type) &
                  t.walletId.equals(walletId) &
                  t.amountMillimes.equals(amountMillimes) &
                  t.occurredAt.isBiggerOrEqualValue(since),
            ))
            .get();
    for (final r in rows) {
      if (r.categoryId == categoryId && inWindow(r.occurredAt, now)) {
        return r;
      }
    }
    return null;
  }
}
