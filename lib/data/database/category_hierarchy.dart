import 'package:drift/drift.dart';

import '../../core/l10n/strings.dart';
import 'app_db.dart';

/// Single-level category hierarchy (parent → child, no grandchildren).
///
/// [parentId] on [Categories] holds the parent row id (null = top-level).
/// Plain-text ref, no FK — consistent with the rest of the schema:
/// archiving never breaks history. Free-form: any parent/child combo is
/// allowed and transactions may sit on parents too; parent totals roll up
/// own transactions + children sums, counted exactly once.
abstract final class CategoryHierarchy {
  /// Default child nameKey -> parent nameKey. User customs and unlisted
  /// keys (e.g. the catch-all `cat_other`) stay top-level (parentId null).
  static const Map<String, String> childParent = {
    'cat_groceries': 'cat_food_drinks',
    'cat_restaurants': 'cat_food_drinks',
    'cat_cafe': 'cat_food_drinks',
    'cat_fastfood': 'cat_food_drinks',
    'cat_taxi': 'cat_transport',
    'cat_louage': 'cat_transport',
    'cat_bus': 'cat_transport',
    'cat_metro': 'cat_transport',
    'cat_fuel': 'cat_transport',
    'cat_steg': 'cat_home_bills',
    'cat_sonede': 'cat_home_bills',
    'cat_internet': 'cat_home_bills',
    'cat_mobile': 'cat_home_bills',
    'cat_household': 'cat_home',
    'cat_clothing': 'cat_shopping',
    'cat_electronics': 'cat_shopping',
    'cat_health': 'cat_health_fitness',
    'cat_gym': 'cat_health_fitness',
    'cat_entertainment': 'cat_lifestyle',
    'inc_salary': 'inc_earnings',
    'inc_freelance': 'inc_earnings',
    'inc_investment': 'inc_earnings',
    'inc_gift': 'inc_earnings',
    'inc_allowance': 'inc_earnings',
    'inc_refund': 'inc_earnings',
    'inc_other_income': 'inc_earnings',
  };

  /// System parent keys of the previous taxonomy. Used by [remapParents]
  /// to move default children whose grouping changed (e.g. clothing
  /// lifestyle → shopping) without touching rows the user deliberately
  /// moved under a custom parent.
  static const Set<String> legacyParentKeys = {
    'cat_food_drinks',
    'cat_transport',
    'cat_home_bills',
    'cat_lifestyle',
    'inc_earnings',
  };

  static String? parentNameKeyFor(String? nameKey) => childParent[nameKey];

  /// Display name with hierarchy: "Parent › Child" for children, plain
  /// name otherwise (mirrors [Strings.categoryName] resolution).
  static String displayName(
    String lang,
    Category c,
    Map<String, Category> byId,
  ) {
    final own = Strings.categoryName(lang, c.nameKey, c.customName);
    final parent = c.parentId == null ? null : byId[c.parentId];
    if (parent == null) return own;
    return '${Strings.categoryName(lang, parent.nameKey, parent.customName)} › $own';
  }

  /// Remap after taxonomy upgrades. Pre-existing rows keep every value
  /// except parentId, and only when the current link is stale-but-systemic:
  /// null links are filled (same as [backfill]) and links pointing at a
  /// *legacy system parent* that no longer matches [childParent] move to
  /// the new parent. Rows the user deliberately moved under a custom
  /// parent are never touched. Idempotent.
  static Future<void> remapParents(AppDb db) async {
    final rows = await db.select(db.categories).get();
    final idByNameKey = <String, String>{};
    final keyById = <String, String>{};
    for (final c in rows) {
      if (c.nameKey != null) {
        idByNameKey[c.nameKey!] = c.id;
        keyById[c.id] = c.nameKey!;
      }
    }
    for (final entry in childParent.entries) {
      final childId = idByNameKey[entry.key];
      final newParentId = idByNameKey[entry.value];
      if (childId == null || newParentId == null) continue;
      final current = rows.singleWhere((c) => c.id == childId);
      if (current.parentId == newParentId) continue;
      final currentParentKey = current.parentId == null
          ? null
          : keyById[current.parentId];
      final stale =
          current.parentId == null ||
          (currentParentKey != null &&
              legacyParentKeys.contains(currentParentKey) &&
              currentParentKey != entry.value);
      if (!stale) continue;
      await db.customUpdate(
        'UPDATE categories SET parent_id=? WHERE id=?',
        variables: [
          Variable.withString(newParentId),
          Variable.withString(childId),
        ],
        updates: {db.categories},
      );
    }
  }

  /// Backfill after the v5 upgrade. Pre-v5 rows keep every value; only
  /// parentId is derived from their nameKey (unknown keys stay top-level).
  static Future<void> backfill(AppDb db) async {
    // Resolve parent row ids by nameKey once.
    final rows = await db.select(db.categories).get();
    final idByNameKey = <String, String>{};
    for (final c in rows) {
      if (c.nameKey != null) idByNameKey[c.nameKey!] = c.id;
    }
    for (final entry in childParent.entries) {
      final parentId = idByNameKey[entry.value];
      if (parentId == null) continue;
      await db.customUpdate(
        'UPDATE categories SET parent_id=? '
        'WHERE name_key=? AND (parent_id IS NULL)',
        variables: [
          Variable.withString(parentId),
          Variable.withString(entry.key),
        ],
        updates: {db.categories},
      );
    }
  }

  /// Pure rollup: every parent total = own transactions + children sums.
  /// Children keep their own totals; the null (uncategorized) bucket passes
  /// through untouched. Parents with no own transactions still gain an
  /// entry from their children. No double-counting by construction.
  static Map<String?, int> rollUp(
    Map<String?, int> byCategory,
    List<Category> cats,
  ) {
    final totals = Map<String?, int>.from(byCategory);
    final byId = <String, Category>{for (final c in cats) c.id: c};
    byCategory.forEach((id, amount) {
      if (id == null) return;
      final parentId = byId[id]?.parentId;
      if (parentId != null) {
        totals[parentId] = (totals[parentId] ?? 0) + amount;
      }
    });
    return totals;
  }
}
