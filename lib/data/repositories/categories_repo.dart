import 'package:drift/drift.dart';

import '../../core/l10n/strings.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';
import '../database/category_hierarchy.dart';
import '../database/category_priority.dart';

class CategoriesRepo {
  final AppDb db;
  CategoriesRepo(this.db);

  Stream<List<Category>> watch({
    bool includeArchived = false,
    List<String>? kinds,
  }) {
    final q = db.select(db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    if (kinds != null && kinds.isNotEmpty) {
      q.where((c) => c.kind.isIn(kinds));
    }
    return q.watch();
  }

  Future<List<Category>> all({
    bool includeArchived = true,
    List<String>? kinds,
  }) {
    final q = db.select(db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    if (kinds != null && kinds.isNotEmpty) {
      q.where((c) => c.kind.isIn(kinds));
    }
    return q.get();
  }

  /// Seed Tunisian defaults once (idempotent per key).
  /// Expense and income defaults seed independently so v2 databases
  /// upgrading to v3 still gain the income set. Parents seed first so
  /// children can link; pre-existing rows gain parents via backfill and
  /// stale system links move via remap (user moves under custom parents
  /// are never touched).
  Future<void> seedDefaults() async {
    final existing = await all(includeArchived: true);
    final idsByKey = <String, String>{
      for (final c in existing)
        if (c.nameKey != null) c.nameKey!: c.id,
    };
    var order = await _maxOrder() + 1;
    for (final (key, icon, kind) in Strings.defaultParentCategories) {
      if (idsByKey.containsKey(key)) continue;
      final id = newId();
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion(
              id: Value(id),
              nameKey: Value(key),
              icon: Value(icon),
              kind: Value(kind),
              priority: Value(CategoryPriority.forNameKey(key)),
              sortOrder: Value(order++),
            ),
          );
      idsByKey[key] = id;
    }
    for (final defs in [
      (Strings.defaultCategories, 'expense'),
      (Strings.defaultIncomeCategories, 'income'),
    ]) {
      for (final (key, icon) in defs.$1) {
        if (idsByKey.containsKey(key)) continue;
        final parentKey = CategoryHierarchy.parentNameKeyFor(key);
        final parentId = parentKey == null ? null : idsByKey[parentKey];
        final id = newId();
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion(
                id: Value(id),
                nameKey: Value(key),
                icon: Value(icon),
                kind: Value(defs.$2),
                priority: Value(CategoryPriority.forNameKey(key)),
                parentId: parentId == null
                    ? const Value.absent()
                    : Value(parentId),
                sortOrder: Value(order++),
              ),
            );
        idsByKey[key] = id;
      }
    }
    // Upgrade path: pre-v5 rows with known keys gain their parent, and
    // rows grouped under a retired system parent move to the new one.
    await CategoryHierarchy.backfill(db);
    await CategoryHierarchy.remapParents(db);
  }

  /// Top-level categories only (parentId null), in sort order.
  Future<List<Category>> roots({
    bool includeArchived = true,
    List<String>? kinds,
  }) async {
    final cats = await all(includeArchived: includeArchived, kinds: kinds);
    return cats.where((c) => c.parentId == null).toList();
  }

  /// Direct children of [parentId], in sort order.
  Future<List<Category>> childrenOf(
    String parentId, {
    bool includeArchived = true,
  }) async {
    final q = db.select(db.categories)
      ..where((c) => c.parentId.equals(parentId))
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    return q.get();
  }

  /// Forest of (parent, children) in sort order. Orphans whose parent is
  /// filtered out appear as their own roots so nothing vanishes from UI.
  Future<List<({Category parent, List<Category> children})>> tree({
    bool includeArchived = true,
    List<String>? kinds,
  }) async {
    final cats = await all(includeArchived: includeArchived, kinds: kinds);
    final byId = {for (final c in cats) c.id: c};
    final kids = <String, List<Category>>{};
    for (final c in cats) {
      if (c.parentId != null) {
        (kids[c.parentId!] ??= []).add(c);
      }
    }
    return [
      for (final c in cats)
        if (c.parentId == null || !byId.containsKey(c.parentId))
          (parent: c, children: kids[c.id] ?? const []),
    ];
  }

  Future<String> create(
    String name, {
    String icon = 'other',
    String kind = 'expense',
    String priority = CategoryPriority.normal,
    String? parentId,
  }) async {
    if (!CategoryPriority.isValid(priority)) {
      throw ArgumentError('bad priority');
    }
    final id = newId();
    await _checkParent(id, parentId);
    final maxOrder = await _maxOrder();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion(
            id: Value(id),
            customName: Value(name.trim()),
            icon: Value(icon),
            kind: Value(kind),
            priority: Value(priority),
            parentId: parentId == null ? const Value.absent() : Value(parentId),
            sortOrder: Value(maxOrder + 1),
          ),
        );
    return id;
  }

  /// Move [id] under [parentId] (null = make top-level). Enforces
  /// single-level: parents must be top-level, no self-parenting, and a
  /// category with children can never become a child.
  Future<void> setParent(String id, String? parentId) async {
    await _checkParent(id, parentId);
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      parentId == null
          ? const CategoriesCompanion(parentId: Value(null))
          : CategoriesCompanion(parentId: Value(parentId)),
    );
  }

  Future<void> _checkParent(String id, String? parentId) async {
    if (parentId == null) return;
    if (parentId == id) throw ArgumentError('self-parent');
    final parent = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(parentId))).getSingleOrNull();
    if (parent == null) throw ArgumentError('unknown parent');
    if (parent.parentId != null) {
      throw ArgumentError('single level only');
    }
    final kids = await childrenOf(id);
    if (kids.isNotEmpty) throw ArgumentError('single level only');
  }

  Future<int> _maxOrder() async {
    final q = db.selectOnly(db.categories)
      ..addColumns([db.categories.sortOrder.max()]);
    final row = await q.getSingleOrNull();
    return row?.read(db.categories.sortOrder.max()) ?? 0;
  }

  Future<void> rename(String id, String name) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(customName: Value(name.trim())),
      );

  /// Move [id] one step within its sibling group (same parent + kind).
  /// [delta] < 0 moves up, > 0 moves down. Swaps sortOrder with the
  /// neighbour so ordering stays dense and stable. No-op at the edges.
  Future<void> move(String id, int delta) async {
    if (delta == 0) return;
    final allCats = await all(includeArchived: true);
    final me = allCats.where((c) => c.id == id).firstOrNull;
    if (me == null) return;
    final siblings =
        allCats
            .where((c) => c.kind == me.kind && c.parentId == me.parentId)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final i = siblings.indexWhere((c) => c.id == id);
    final j = (i + (delta < 0 ? -1 : 1)).clamp(0, siblings.length - 1);
    if (i == j) return;
    final other = siblings[j];
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(sortOrder: Value(other.sortOrder)),
    );
    await (db.update(db.categories)..where((c) => c.id.equals(other.id))).write(
      CategoriesCompanion(sortOrder: Value(me.sortOrder)),
    );
  }

  Future<void> setIcon(String id, String icon) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(icon: Value(icon)),
      );

  Future<void> setPriority(String id, String priority) {
    if (!CategoryPriority.isValid(priority)) {
      throw ArgumentError('bad priority');
    }
    return (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(priority: Value(priority)),
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(isArchived: Value(archived)),
    );
    if (archived) {
      // Archiving a parent cascades to its children.
      await (db.update(db.categories)..where((c) => c.parentId.equals(id)))
          .write(const CategoriesCompanion(isArchived: Value(true)));
    }
  }

  /// Delete [id]. Blocked while children exist (UI maps the error to a
  /// localized message); archive cascades instead.
  Future<void> delete(String id) async {
    final kids = await childrenOf(id);
    if (kids.isNotEmpty) throw StateError('has-children');
    await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
  }
}
