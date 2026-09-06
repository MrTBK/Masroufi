import 'package:drift/drift.dart';

import '../../core/l10n/strings.dart';
import '../../core/utils/utils.dart';
import '../database/app_db.dart';

class CategoriesRepo {
  final AppDb db;
  CategoriesRepo(this.db);

  Stream<List<Category>> watch({bool includeArchived = false}) {
    final q = db.select(db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    return q.watch();
  }

  Future<List<Category>> all({bool includeArchived = true}) {
    final q = db.select(db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (!includeArchived) q.where((c) => c.isArchived.equals(false));
    return q.get();
  }

  /// Seed Tunisian defaults once (idempotent).
  Future<void> seedDefaults() async {
    final count = await db.select(db.categories).get().then((v) => v.length);
    if (count > 0) return;
    var order = 0;
    for (final (key, icon) in Strings.defaultCategories) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion(
              id: Value(newId()),
              nameKey: Value(key),
              icon: Value(icon),
              sortOrder: Value(order++),
            ),
          );
    }
  }

  Future<String> create(String name) async {
    final id = newId();
    final maxOrder = await _maxOrder();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion(
            id: Value(id),
            customName: Value(name.trim()),
            sortOrder: Value(maxOrder + 1),
          ),
        );
    return id;
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

  Future<void> setArchived(String id, bool archived) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(isArchived: Value(archived)),
      );
}
