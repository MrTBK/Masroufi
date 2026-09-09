import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/database/category_hierarchy.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';

void main() {
  group('hierarchy seed', () {
    late AppDb db;
    late CategoriesRepo cats;
    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      cats = CategoriesRepo(db);
    });
    tearDown(() => db.close());

    test('seed creates 10 parents over 27 children', () async {
      await cats.seedDefaults();
      final allCats = await cats.all();
      expect(allCats.length, 37);
      final byKey = {for (final c in allCats) c.nameKey: c};
      for (final (key, _, _) in Strings.defaultParentCategories) {
        expect(byKey[key]?.parentId, isNull, reason: key);
      }
      // Spot-check child links.
      expect(byKey['cat_cafe']?.parentId, byKey['cat_food_drinks']?.id);
      expect(byKey['cat_taxi']?.parentId, byKey['cat_transport']?.id);
      expect(byKey['cat_steg']?.parentId, byKey['cat_home_bills']?.id);
      expect(byKey['cat_clothing']?.parentId, byKey['cat_shopping']?.id);
      expect(byKey['cat_household']?.parentId, byKey['cat_home']?.id);
      expect(byKey['cat_health']?.parentId, byKey['cat_health_fitness']?.id);
      expect(byKey['cat_gym']?.parentId, byKey['cat_health_fitness']?.id);
      expect(byKey['cat_entertainment']?.parentId, byKey['cat_lifestyle']?.id);
      expect(byKey['inc_salary']?.parentId, byKey['inc_earnings']?.id);
      expect(byKey['inc_gift']?.parentId, byKey['inc_earnings']?.id);
      // The catch-all stays top-level.
      expect(byKey['cat_other']?.parentId, isNull);
    });

    test('tree groups children under kind-matched parents', () async {
      await cats.seedDefaults();
      final forest = await cats.tree();
      final food = forest.singleWhere(
        (n) => n.parent.nameKey == 'cat_food_drinks',
      );
      expect(
        food.children.map((c) => c.nameKey),
        containsAll(['cat_groceries', 'cat_restaurants', 'cat_cafe']),
      );
      final roots = await cats.roots();
      expect(
        roots.where((c) => c.kind == 'expense').length,
        10, // 9 parents + cat_other
      );
      expect(
        roots.where((c) => c.kind == 'income').length,
        1, // inc_earnings only; all income leaves parented
      );
      final kids = await cats.childrenOf(food.parent.id);
      expect(kids.length, 4);
      final bills = forest.singleWhere(
        (n) => n.parent.nameKey == 'cat_home_bills',
      );
      expect(
        bills.children.map((c) => c.nameKey),
        containsAll(['cat_steg', 'cat_sonede', 'cat_internet', 'cat_mobile']),
      );
      final shopping = forest.singleWhere(
        (n) => n.parent.nameKey == 'cat_shopping',
      );
      expect(
        shopping.children.map((c) => c.nameKey),
        containsAll(['cat_clothing', 'cat_electronics']),
      );
      final earnings = forest.singleWhere(
        (n) => n.parent.nameKey == 'inc_earnings',
      );
      expect(earnings.children.length, 7);
    });
  });

  group('hierarchy rules', () {
    late AppDb db;
    late CategoriesRepo cats;
    setUp(() {
      db = AppDb.forTesting(NativeDatabase.memory());
      cats = CategoriesRepo(db);
    });
    tearDown(() => db.close());

    test('create links child, rejects unknown parent', () async {
      final parent = await cats.create('Dining');
      final child = await cats.create('Cafe', parentId: parent);
      expect((await cats.childrenOf(parent)).map((c) => c.id), [child]);
      await expectLater(
        () => cats.create('X', parentId: 'no-such-id'),
        throwsArgumentError,
      );
    });

    test('self-parent and two-level nesting rejected', () async {
      final parent = await cats.create('Dining');
      final child = await cats.create('Cafe', parentId: parent);
      await expectLater(
        () => cats.setParent(parent, parent),
        throwsArgumentError,
      );
      // A child can never become a parent (would make grandchildren).
      await expectLater(
        () => cats.create('Beans', parentId: child),
        throwsArgumentError,
      );
      // A parent can never become a child.
      final other = await cats.create('Other');
      await expectLater(
        () => cats.setParent(parent, other),
        throwsArgumentError,
      );
      // Unlinking back to top-level is allowed.
      await cats.setParent(child, null);
      final after = await cats.all();
      expect(after.singleWhere((c) => c.id == child).parentId, isNull);
    });

    test('archive cascades down only', () async {
      final parent = await cats.create('Dining');
      final child = await cats.create('Cafe', parentId: parent);
      await cats.setArchived(parent, true);
      final archived = await cats.all(includeArchived: true);
      expect(archived.singleWhere((c) => c.id == child).isArchived, isTrue);
      // Unarchiving the parent leaves the intentionally-archived child.
      await cats.setArchived(parent, false);
      final reopened = await cats.all(includeArchived: true);
      expect(reopened.singleWhere((c) => c.id == child).isArchived, isTrue);
    });

    test('delete blocked while children exist', () async {
      final parent = await cats.create('Dining');
      final child = await cats.create('Cafe', parentId: parent);
      await expectLater(() => cats.delete(parent), throwsStateError);
      await cats.delete(child);
      await cats.delete(parent);
      expect(await cats.all(), isEmpty);
    });
  });

  group('CategoryHierarchy.rollUp', () {
    test('parents sum own + children exactly once', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final allCats = await cats.all();
      final byKey = {for (final c in allCats) c.nameKey: c};
      final food = byKey['cat_food_drinks']!.id;
      final cafe = byKey['cat_cafe']!.id;
      final rolled = CategoryHierarchy.rollUp({
        cafe: 7000,
        food: 3000,
      }, allCats);
      expect(rolled[food], 10000);
      expect(rolled[cafe], 7000);
    });

    test('childless-parent gains entry, null passes through', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final allCats = await cats.all();
      final byKey = {for (final c in allCats) c.nameKey: c};
      final food = byKey['cat_food_drinks']!.id;
      final cafe = byKey['cat_cafe']!.id;
      final rolled = CategoryHierarchy.rollUp({cafe: 7000, null: 500}, allCats);
      expect(rolled[food], 7000);
      expect(rolled[null], 500);
    });

    test('displayName renders Parent › Child', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final allCats = await cats.all();
      final byId = {for (final c in allCats) c.id: c};
      final byKey = {for (final c in allCats) c.nameKey: c};
      expect(
        CategoryHierarchy.displayName('en', byKey['cat_cafe']!, byId),
        'Food & Drinks › Café',
      );
      expect(
        CategoryHierarchy.displayName('en', byKey['cat_other']!, byId),
        'Other',
      );
    });
  });

  group('hierarchy remap', () {
    test('stale system links move, custom moves preserved', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final before = await cats.all();
      final byKey = {for (final c in before) c.nameKey: c};
      // Simulate the old taxonomy: clothing under lifestyle, gift top-level.
      await cats.setParent(
        byKey['cat_clothing']!.id,
        byKey['cat_lifestyle']!.id,
      );
      await cats.setParent(byKey['inc_gift']!.id, null);
      // User deliberately moves groceries under a custom parent.
      final custom = await cats.create('Kids');
      await cats.setParent(byKey['cat_groceries']!.id, custom);
      await CategoryHierarchy.remapParents(db);
      final after = await cats.all();
      final afterByKey = {for (final c in after) c.nameKey: c};
      expect(
        afterByKey['cat_clothing']!.parentId,
        afterByKey['cat_shopping']!.id,
      );
      expect(afterByKey['inc_gift']!.parentId, afterByKey['inc_earnings']!.id);
      // Custom placement untouched.
      expect(afterByKey['cat_groceries']!.parentId, custom);
      // Idempotent.
      await CategoryHierarchy.remapParents(db);
      final again = await cats.all();
      expect(
        again.singleWhere((c) => c.nameKey == 'cat_groceries').parentId,
        custom,
      );
    });

    test('move swaps sibling order within the same group', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cats = CategoriesRepo(db);
      await cats.seedDefaults();
      final food = (await cats.all()).singleWhere(
        (c) => c.nameKey == 'cat_food_drinks',
      );
      // Collect initial child order, move first child down, verify swap.
      final kids0 = await cats.childrenOf(food.id);
      expect(kids0.length, 4);
      await cats.move(kids0.first.id, 1);
      final kids1 = await cats.childrenOf(food.id);
      expect(kids1[1].id, kids0.first.id);
      expect(kids1[0].id, kids0[1].id);
      // Moving past the edge is a no-op.
      await cats.move(kids1.first.id, -5);
      final kids2 = await cats.childrenOf(food.id);
      expect(kids2.first.id, kids1.first.id);
      // A move never leaks across groups.
      final transport = (await cats.all()).singleWhere(
        (c) => c.nameKey == 'cat_transport',
      );
      final transportKids = await cats.childrenOf(transport.id);
      expect(transportKids.map((c) => c.id), isNot(contains(kids0.first.id)));
    });
  });

  group('hierarchy backfill', () {
    test('pre-v5 rows link by nameKey, customs stay top-level', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion(
              id: const Value('p1'),
              nameKey: const Value('cat_food_drinks'),
              icon: const Value('restaurant'),
              kind: const Value('expense'),
              sortOrder: const Value(1),
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion(
              id: const Value('c1'),
              nameKey: const Value('cat_cafe'),
              icon: const Value('coffee'),
              kind: const Value('expense'),
              sortOrder: const Value(2),
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion(
              id: const Value('c2'),
              customName: const Value('My Hobby'),
              icon: const Value('other'),
              kind: const Value('expense'),
              sortOrder: const Value(3),
            ),
          );
      await CategoryHierarchy.backfill(db);
      final byId = {
        for (final c in await db.select(db.categories).get()) c.id: c,
      };
      expect(byId['c1']!.parentId, 'p1');
      expect(byId['c2']!.parentId, isNull);
      // Idempotent: re-running never overwrites explicit links.
      await db.customUpdate(
        'UPDATE categories SET parent_id=? WHERE id=?',
        variables: [Variable.withString('other'), Variable.withString('c1')],
        updates: {db.categories},
      );
      await CategoryHierarchy.backfill(db);
      final relinked = await db.select(db.categories).get();
      expect(relinked.singleWhere((c) => c.id == 'c1').parentId, 'other');
    });
  });
}
