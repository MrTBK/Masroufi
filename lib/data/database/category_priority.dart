import 'package:drift/drift.dart';

import 'app_db.dart';

/// Priority classification for expense categories: the financial nature
/// of a category (important | normal | fun). Stored as a stable string
/// key in SQLite; UI labels resolve via localized strings. Category
/// color/icon stay primary — priority is secondary analytical metadata.
///
/// Priority is inherited from the category: transactions carry no
/// priority field. Income kinds keep 'normal' but it is never read.
abstract final class CategoryPriority {
  static const String important = 'important';
  static const String normal = 'normal';
  static const String fun = 'fun';

  static const List<String> values = [important, normal, fun];

  static bool isValid(String? v) => v == important || v == normal || v == fun;

  /// Deterministic defaults for built-in expense categories (by nameKey).
  /// Custom categories, income kinds and anything unlisted → [normal].
  static const Map<String, String> defaults = {
    'cat_groceries': important,
    'cat_steg': important,
    'cat_sonede': important,
    'cat_internet': important,
    'cat_mobile': important,
    'cat_fuel': important,
    'cat_taxi': important,
    'cat_louage': important,
    'cat_bus': important,
    'cat_metro': important,
    'cat_health': important,
    'cat_household': important,
    'cat_clothing': normal,
    'cat_electronics': normal,
    'cat_restaurants': normal,
    'cat_cafe': normal,
    'cat_gym': normal,
    'cat_other': normal,
    'cat_fastfood': fun,
    'cat_entertainment': fun,
  };

  static String forNameKey(String? nameKey) => defaults[nameKey] ?? normal;

  /// Backfill after the v4 upgrade. Existing rows keep every value;
  /// only priority is derived from their nameKey.
  static Future<void> backfill(AppDb db) async {
    for (final entry in defaults.entries) {
      await db.customUpdate(
        'UPDATE categories SET priority=? WHERE name_key=?',
        variables: [
          Variable.withString(entry.value),
          Variable.withString(entry.key),
        ],
        updates: {db.categories},
      );
    }
  }
}
