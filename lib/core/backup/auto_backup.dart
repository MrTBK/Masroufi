import 'dart:io';

import '../../data/database/app_db.dart';
import '../../features/backup/backup_codec.dart';

/// Weekly auto-backup (Track 5, no schema).
///
/// - Runs on app start when stale (no run in the last 7 days).
/// - Files: `masroufi_auto_<epoch>.json` in the app documents dir.
/// - Keeps the newest 4, deletes older (filename-rotated).
/// - Last-run marker: `auto_backup_at` KV (ISO-8601 UTC).
/// - Best-effort: callers wrap in try/catch; never blocks startup.
/// - Content: same full-fidelity JSON as manual backup (codec v7+).
abstract final class AutoBackup {
  static const keepLast = 4;
  static const staleAfter = Duration(days: 7);
  static const nagAfter = Duration(days: 14);

  /// Pure: should a run happen now?
  static bool shouldRun({required DateTime? lastRun, required DateTime now}) {
    if (lastRun == null) return true;
    return now.difference(lastRun) >= staleAfter;
  }

  /// Pure: should the backup-health nag show? Dismissible via
  /// [dismissedAt]: hidden when dismissed after the last backup.
  static bool shouldNag({
    required DateTime? lastBackup,
    required DateTime? dismissedAt,
    required DateTime now,
  }) {
    if (lastBackup == null) return true;
    if (now.difference(lastBackup) < nagAfter) return false;
    if (dismissedAt != null && !dismissedAt.isBefore(lastBackup)) {
      return false;
    }
    return true;
  }

  /// Pure: given auto-backup filenames (full paths), which to delete to
  /// keep the newest [keepLast]? Sorts lexicographically (epoch in name).
  static List<String> prune(List<String> files, {int keep = keepLast}) {
    if (files.length <= keep) return const [];
    final sorted = [...files]..sort();
    return sorted.sublist(0, sorted.length - keep);
  }

  static Future<DateTime?> lastAutoAt(AppDb db) async {
    final row =
        await (db.select(
          db.appSettings,
        )..where((s) => s.key.equals('auto_backup_at'))).getSingleOrNull();
    if (row == null) return null;
    try {
      return DateTime.parse(row.value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setAutoAt(AppDb db, DateTime when) =>
      db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSetting(
              key: 'auto_backup_at',
              value: when.toUtc().toIso8601String(),
            ),
          );

  /// Run when stale: writes one auto file, prunes to [keepLast], stamps
  /// `auto_backup_at` + `last_backup_at`. Returns the new file or null
  /// when skipped. Never throws (returns null on any failure).
  static Future<File?> runIfStale(AppDb db, Directory dir) async {
    try {
      final now = DateTime.now();
      final last = await lastAutoAt(db);
      if (!shouldRun(lastRun: last, now: now)) return null;
      final backup = BackupCodec.build({
        'wallets': [
          for (final w in await db.select(db.wallets).get())
            {
              'id': w.id,
              'name': w.name,
              'icon': w.icon,
              'initialMillimes': w.initialMillimes,
              'currency': w.currency,
              'isArchived': w.isArchived,
              'isBalanceHidden': w.isBalanceHidden,
              'colorKey': w.colorKey,
              'design': w.design,
              'createdAt': w.createdAt.toIso8601String(),
              'updatedAt': w.updatedAt.toIso8601String(),
            },
        ],
        'categories': [
          for (final c in await db.select(db.categories).get())
            {
              'id': c.id,
              'nameKey': c.nameKey,
              'customName': c.customName,
              'icon': c.icon,
              'kind': c.kind,
              'priority': c.priority,
              'parentId': c.parentId,
              'isArchived': c.isArchived,
              'sortOrder': c.sortOrder,
            },
        ],
        'transactions': [
          for (final t in await db.select(db.transactions).get())
            {
              'id': t.id,
              'type': t.type,
              'amountMillimes': t.amountMillimes,
              'walletId': t.walletId,
              'toWalletId': t.toWalletId,
              'categoryId': t.categoryId,
              'recurringRuleId': t.recurringRuleId,
              'origMinor': t.origMinor,
              'origCurrency': t.origCurrency,
              'occurredAt': t.occurredAt.toIso8601String(),
              'note': t.note,
              'createdAt': t.createdAt.toIso8601String(),
              'updatedAt': t.updatedAt.toIso8601String(),
            },
        ],
        'budgets': [
          for (final b in await db.select(db.budgets).get())
            {
              'id': b.id,
              'year': b.year,
              'month': b.month,
              'amountMillimes': b.amountMillimes,
            },
        ],
        'settings': [
          for (final s in await db.select(db.appSettings).get())
            {'key': s.key, 'value': s.value},
        ],
        'recurring_rules': [
          for (final r in await db.select(db.recurringRules).get())
            {
              'id': r.id,
              'type': r.type,
              'amountMillimes': r.amountMillimes,
              'walletId': r.walletId,
              'categoryId': r.categoryId,
              'note': r.note,
              'frequency': r.frequency,
              'startDate': r.startDate.toIso8601String(),
              'endDate': r.endDate?.toIso8601String(),
              'nextOccurrence': r.nextOccurrence.toIso8601String(),
              'lastGenerated': r.lastGenerated?.toIso8601String(),
              'isActive': r.isActive,
              'createdAt': r.createdAt.toIso8601String(),
              'updatedAt': r.updatedAt.toIso8601String(),
            },
        ],
        'category_budgets': [
          for (final b in await db.select(db.categoryBudgets).get())
            {
              'id': b.id,
              'categoryId': b.categoryId,
              'year': b.year,
              'month': b.month,
              'amountMillimes': b.amountMillimes,
            },
        ],
        'savings_goals': [
          for (final g in await db.select(db.savingsGoals).get())
            {
              'id': g.id,
              'name': g.name,
              'targetMillimes': g.targetMillimes,
              'targetDate': g.targetDate?.toIso8601String(),
              'walletId': g.walletId,
              'isArchived': g.isArchived,
            },
        ],
        'savings_contributions': [
          for (final c in await db.select(db.savingsContributions).get())
            {
              'id': c.id,
              'goalId': c.goalId,
              'amountMillimes': c.amountMillimes,
              'occurredAt': c.occurredAt.toIso8601String(),
              'note': c.note,
            },
        ],
        'debts': [
          for (final d in await db.select(db.debts).get())
            {
              'id': d.id,
              'person': d.person,
              'direction': d.direction,
              'originalMillimes': d.originalMillimes,
              'occurredAt': d.occurredAt.toIso8601String(),
              'dueDate': d.dueDate?.toIso8601String(),
              'notes': d.notes,
              'status': d.status,
            },
        ],
        'debt_payments': [
          for (final p in await db.select(db.debtPayments).get())
            {
              'id': p.id,
              'debtId': p.debtId,
              'amountMillimes': p.amountMillimes,
              'walletId': p.walletId,
              'txnId': p.txnId,
              'occurredAt': p.occurredAt.toIso8601String(),
              'note': p.note,
            },
        ],
        'txn_templates': [
          for (final t in await db.select(db.txnTemplates).get())
            {
              'id': t.id,
              'name': t.name,
              'type': t.type,
              'amountMillimes': t.amountMillimes,
              'walletId': t.walletId,
              'toWalletId': t.toWalletId,
              'categoryId': t.categoryId,
              'note': t.note,
              'sortOrder': t.sortOrder,
              'createdAt': t.createdAt.toIso8601String(),
            },
        ],
        'txn_splits': [
          for (final s in await db.select(db.txnSplits).get())
            {
              'id': s.id,
              'txnId': s.txnId,
              'categoryId': s.categoryId,
              'amountMillimes': s.amountMillimes,
              'note': s.note,
              'createdAt': s.createdAt.toIso8601String(),
            },
        ],
      });
      final file = File(
        '${dir.path}/masroufi_auto_${now.millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(BackupCodec.encode(backup));
      // Prune old auto files (best-effort).
      try {
        final autos = dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(
              (p) =>
                  p.contains('masroufi_auto_') && p.endsWith('.json'),
            )
            .toList();
        for (final dead in prune(autos)) {
          try {
            await File(dead).delete();
          } catch (_) {}
        }
      } catch (_) {}
      await setAutoAt(db, now);
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSetting(
              key: 'last_backup_at',
              value: now.toUtc().toIso8601String(),
            ),
          );
      return file;
    } catch (_) {
      return null;
    }
  }
}
