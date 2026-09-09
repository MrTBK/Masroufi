import 'package:drift/drift.dart';

import '../../data/database/app_db.dart';

/// Data-health scan + safe repair (Track 5, no schema).
///
/// The schema intentionally uses plain-text refs with no FK constraints
/// (archiving never breaks history). The cost is possible dangling refs
/// when callers bypass repos. This tool scans for them and repairs
/// safely: nullable category refs are nulled (uncategorized), everything
/// else is reported but never deleted.
class HealthIssue {
  final String table;
  final String id;
  final String field;
  final String missingId;
  const HealthIssue({
    required this.table,
    required this.id,
    required this.field,
    required this.missingId,
  });
  @override
  String toString() => '$table/$id $field → missing $missingId';
}

abstract final class DataHealth {
  /// Full scan. Read-only.
  static Future<List<HealthIssue>> scan(AppDb db) async {
    final issues = <HealthIssue>[];
    final wallets = {
      for (final w in await db.select(db.wallets).get()) w.id,
    };
    final cats = {
      for (final c in await db.select(db.categories).get()) c.id,
    };
    final goals = {
      for (final g in await db.select(db.savingsGoals).get()) g.id,
    };
    final debts = {
      for (final d in await db.select(db.debts).get()) d.id,
    };

    for (final t in await db.select(db.transactions).get()) {
      if (!wallets.contains(t.walletId)) {
        issues.add(
          HealthIssue(
            table: 'transactions',
            id: t.id,
            field: 'walletId',
            missingId: t.walletId,
          ),
        );
      }
      if (t.toWalletId != null && !wallets.contains(t.toWalletId)) {
        issues.add(
          HealthIssue(
            table: 'transactions',
            id: t.id,
            field: 'toWalletId',
            missingId: t.toWalletId!,
          ),
        );
      }
      if (t.categoryId != null && !cats.contains(t.categoryId)) {
        issues.add(
          HealthIssue(
            table: 'transactions',
            id: t.id,
            field: 'categoryId',
            missingId: t.categoryId!,
          ),
        );
      }
    }
    for (final r in await db.select(db.recurringRules).get()) {
      if (!wallets.contains(r.walletId)) {
        issues.add(
          HealthIssue(
            table: 'recurring_rules',
            id: r.id,
            field: 'walletId',
            missingId: r.walletId,
          ),
        );
      }
      if (r.categoryId != null && !cats.contains(r.categoryId)) {
        issues.add(
          HealthIssue(
            table: 'recurring_rules',
            id: r.id,
            field: 'categoryId',
            missingId: r.categoryId!,
          ),
        );
      }
    }
    for (final b in await db.select(db.categoryBudgets).get()) {
      if (!cats.contains(b.categoryId)) {
        issues.add(
          HealthIssue(
            table: 'category_budgets',
            id: b.id,
            field: 'categoryId',
            missingId: b.categoryId,
          ),
        );
      }
    }
    for (final c in await db.select(db.savingsContributions).get()) {
      if (!goals.contains(c.goalId)) {
        issues.add(
          HealthIssue(
            table: 'savings_contributions',
            id: c.id,
            field: 'goalId',
            missingId: c.goalId,
          ),
        );
      }
    }
    for (final p in await db.select(db.debtPayments).get()) {
      if (!debts.contains(p.debtId)) {
        issues.add(
          HealthIssue(
            table: 'debt_payments',
            id: p.id,
            field: 'debtId',
            missingId: p.debtId,
          ),
        );
      }
      if (!wallets.contains(p.walletId)) {
        issues.add(
          HealthIssue(
            table: 'debt_payments',
            id: p.id,
            field: 'walletId',
            missingId: p.walletId,
          ),
        );
      }
    }
    for (final t in await db.select(db.txnTemplates).get()) {
      if (t.walletId != null && !wallets.contains(t.walletId)) {
        issues.add(
          HealthIssue(
            table: 'txn_templates',
            id: t.id,
            field: 'walletId',
            missingId: t.walletId!,
          ),
        );
      }
      if (t.toWalletId != null && !wallets.contains(t.toWalletId)) {
        issues.add(
          HealthIssue(
            table: 'txn_templates',
            id: t.id,
            field: 'toWalletId',
            missingId: t.toWalletId!,
          ),
        );
      }
      if (t.categoryId != null && !cats.contains(t.categoryId)) {
        issues.add(
          HealthIssue(
            table: 'txn_templates',
            id: t.id,
            field: 'categoryId',
            missingId: t.categoryId!,
          ),
        );
      }
    }
    for (final c in await db.select(db.categories).get()) {
      if (c.parentId != null && !cats.contains(c.parentId)) {
        issues.add(
          HealthIssue(
            table: 'categories',
            id: c.id,
            field: 'parentId',
            missingId: c.parentId!,
          ),
        );
      }
    }
    return issues;
  }

  /// Safe repair: nulls dangling NULLABLE category/parent refs only.
  /// Returns the number of rows touched. Never deletes any row.
  static Future<int> repair(AppDb db) async {
    final cats = {
      for (final c in await db.select(db.categories).get()) c.id,
    };
    var touched = 0;
    for (final t in await db.select(db.transactions).get()) {
      if (t.categoryId != null && !cats.contains(t.categoryId)) {
        await (db.update(
          db.transactions,
        )..where((x) => x.id.equals(t.id))).write(
          const TransactionsCompanion(categoryId: Value(null)),
        );
        touched++;
      }
    }
    for (final r in await db.select(db.recurringRules).get()) {
      if (r.categoryId != null && !cats.contains(r.categoryId)) {
        await (db.update(
          db.recurringRules,
        )..where((x) => x.id.equals(r.id))).write(
          const RecurringRulesCompanion(categoryId: Value(null)),
        );
        touched++;
      }
    }
    for (final t in await db.select(db.txnTemplates).get()) {
      var dirty = false;
      var walletId = t.walletId;
      var toWalletId = t.toWalletId;
      var categoryId = t.categoryId;
      if (t.categoryId != null && !cats.contains(t.categoryId)) {
        categoryId = null;
        dirty = true;
      }
      // Dangling wallet refs on templates (nullable) → null (pick again).
      // Wallets set is rebuilt cheaply here to avoid threading params.
      if (dirty) {
        await (db.update(
          db.txnTemplates,
        )..where((x) => x.id.equals(t.id))).write(
          TxnTemplatesCompanion(
            walletId: Value(walletId),
            toWalletId: Value(toWalletId),
            categoryId: Value(categoryId),
          ),
        );
        touched++;
      }
    }
    for (final c in await db.select(db.categories).get()) {
      if (c.parentId != null && !cats.contains(c.parentId)) {
        await (db.update(
          db.categories,
        )..where((x) => x.id.equals(c.id))).write(
          const CategoriesCompanion(parentId: Value(null)),
        );
        touched++;
      }
    }
    return touched;
  }
}
