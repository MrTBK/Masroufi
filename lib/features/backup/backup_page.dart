import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/database/category_priority.dart';
import 'backup_codec.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool busy = false;
  String? msg;

  AppDb get db => ref.read(appDbProvider);

  Map<String, dynamic> _walletJson(Wallet w) => {
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
  };

  Map<String, dynamic> _catJson(Category c) => {
    'id': c.id,
    'nameKey': c.nameKey,
    'customName': c.customName,
    'icon': c.icon,
    'kind': c.kind,
    'priority': c.priority,
    'parentId': c.parentId,
    'isArchived': c.isArchived,
    'sortOrder': c.sortOrder,
  };

  Map<String, dynamic> _txnJson(Transaction t) => {
    'id': t.id,
    'type': t.type,
    'amountMillimes': t.amountMillimes,
    'walletId': t.walletId,
    'toWalletId': t.toWalletId,
    'categoryId': t.categoryId,
    'recurringRuleId': t.recurringRuleId,
    // v8 multi-currency (null = plain TND).
    'origMinor': t.origMinor,
    'origCurrency': t.origCurrency,
    'occurredAt': t.occurredAt.toIso8601String(),
    'note': t.note,
    'createdAt': t.createdAt.toIso8601String(),
    'updatedAt': t.updatedAt.toIso8601String(),
  };

  Future<void> createBackup() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      final backup = BackupCodec.build({
        'wallets': [
          for (final w in await db.select(db.wallets).get()) _walletJson(w),
        ],
        'categories': [
          for (final c in await db.select(db.categories).get()) _catJson(c),
        ],
        'transactions': [
          for (final t in await db.select(db.transactions).get()) _txnJson(t),
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
        // v8 splits (empty for older clients; tryDecode normalizes).
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
      final dir = await getApplicationDocumentsDirectory();
      final name =
          'masroufi_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final f = File('${dir.path}/$name');
      await f.writeAsString(BackupCodec.encode(backup));
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: await f.readAsBytes(),
      );
      await ref.read(settingsRepoProvider).setLastBackupAt(DateTime.now());
      if (mounted) setState(() {});
      setState(() => msg = uri?.toString() ?? f.path);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restoreBackup() async {
    final lang = ref.read(languageProvider);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    final decoded = BackupCodec.tryDecode(await File(path).readAsString());
    if (!mounted) return;
    if (decoded == null) {
      setState(() => msg = Strings.get(lang, 'invalidBackup'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Strings.get(lang, 'restoreConfirm')),
        content: Text(Strings.get(lang, 'restoreConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Strings.get(lang, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Strings.get(lang, 'restoreBackup')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await db.transaction(() async {
        await db.delete(db.txnSplits).go();
        await db.delete(db.transactions).go();
        await db.delete(db.budgets).go();
        await db.delete(db.wallets).go();
        await db.delete(db.categories).go();
        await db.delete(db.appSettings).go();
        await db.delete(db.recurringRules).go();
        await db.delete(db.categoryBudgets).go();
        await db.delete(db.savingsContributions).go();
        await db.delete(db.savingsGoals).go();
        await db.delete(db.debtPayments).go();
        await db.delete(db.debts).go();
        await db.delete(db.txnTemplates).go();
        for (final w in decoded['wallets'] as List) {
          await db
              .into(db.wallets)
              .insert(
                WalletsCompanion(
                  id: Value(w['id'] as String),
                  name: Value(w['name'] as String),
                  icon: Value((w['icon'] as String?) ?? 'cash'),
                  initialMillimes: Value((w['initialMillimes'] as num).toInt()),
                  currency: Value((w['currency'] as String?) ?? 'TND'),
                  isArchived: Value((w['isArchived'] as bool?) ?? false),
                  isBalanceHidden: Value(
                    (w['isBalanceHidden'] as bool?) ?? false,
                  ),
                  // v1-v5 backups carry no card styling → defaults.
                  colorKey: Value((w['colorKey'] as String?) ?? 'teal'),
                  design: Value((w['design'] as String?) ?? 'classic'),
                  createdAt: Value(DateTime.parse(w['createdAt'] as String)),
                  updatedAt: Value(DateTime.parse(w['updatedAt'] as String)),
                ),
              );
        }
        for (final c in decoded['categories'] as List) {
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion(
                  id: Value(c['id'] as String),
                  nameKey: Value(c['nameKey'] as String?),
                  customName: Value(c['customName'] as String?),
                  icon: Value((c['icon'] as String?) ?? 'other'),
                  kind: Value((c['kind'] as String?) ?? 'expense'),
                  priority: Value(
                    CategoryPriority.isValid(c['priority'] as String?)
                        ? (c['priority'] as String)
                        : CategoryPriority.forNameKey(c['nameKey'] as String?),
                  ),
                  isArchived: Value((c['isArchived'] as bool?) ?? false),
                  sortOrder: Value((c['sortOrder'] as num?)?.toInt() ?? 0),
                  // v1-v4 backups carry no parentId → top-level, then
                  // backfilled for known default children below.
                  parentId: Value(c['parentId'] as String?),
                ),
              );
        }
        await CategoryHierarchy.backfill(db);
        for (final t in decoded['transactions'] as List) {
          await db
              .into(db.transactions)
              .insert(
                TransactionsCompanion(
                  id: Value(t['id'] as String),
                  type: Value(t['type'] as String),
                  amountMillimes: Value((t['amountMillimes'] as num).toInt()),
                  walletId: Value(t['walletId'] as String),
                  toWalletId: Value(t['toWalletId'] as String?),
                  categoryId: Value(t['categoryId'] as String?),
                  recurringRuleId: Value(t['recurringRuleId'] as String?),
                  // v1-v7 backups carry no originals → plain TND nulls.
                  origMinor: Value((t['origMinor'] as num?)?.toInt()),
                  origCurrency: Value(t['origCurrency'] as String?),
                  occurredAt: Value(DateTime.parse(t['occurredAt'] as String)),
                  note: Value((t['note'] as String?) ?? ''),
                  createdAt: Value(DateTime.parse(t['createdAt'] as String)),
                  updatedAt: Value(DateTime.parse(t['updatedAt'] as String)),
                ),
              );
        }
        for (final b in decoded['budgets'] as List) {
          await db
              .into(db.budgets)
              .insert(
                BudgetsCompanion(
                  id: Value(b['id'] as String),
                  year: Value((b['year'] as num).toInt()),
                  month: Value((b['month'] as num).toInt()),
                  amountMillimes: Value((b['amountMillimes'] as num).toInt()),
                ),
              );
        }
        for (final s in decoded['settings'] as List) {
          await db
              .into(db.appSettings)
              .insert(
                AppSetting(
                  key: s['key'] as String,
                  value: s['value'] as String,
                ),
              );
        }
        // v2 tables (absent/empty in v1 backups — tryDecode normalizes).
        for (final r in (decoded['recurring_rules'] as List? ?? [])) {
          await db
              .into(db.recurringRules)
              .insert(
                RecurringRulesCompanion(
                  id: Value(r['id'] as String),
                  type: Value(r['type'] as String),
                  amountMillimes: Value((r['amountMillimes'] as num).toInt()),
                  walletId: Value(r['walletId'] as String),
                  categoryId: Value(r['categoryId'] as String?),
                  note: Value((r['note'] as String?) ?? ''),
                  frequency: Value(r['frequency'] as String),
                  startDate: Value(DateTime.parse(r['startDate'] as String)),
                  endDate: Value(
                    r['endDate'] == null
                        ? null
                        : DateTime.parse(r['endDate'] as String),
                  ),
                  nextOccurrence: Value(
                    DateTime.parse(r['nextOccurrence'] as String),
                  ),
                  lastGenerated: Value(
                    r['lastGenerated'] == null
                        ? null
                        : DateTime.parse(r['lastGenerated'] as String),
                  ),
                  isActive: Value((r['isActive'] as bool?) ?? true),
                  createdAt: Value(DateTime.parse(r['createdAt'] as String)),
                  updatedAt: Value(DateTime.parse(r['updatedAt'] as String)),
                ),
              );
        }
        for (final b in (decoded['category_budgets'] as List? ?? [])) {
          await db
              .into(db.categoryBudgets)
              .insert(
                CategoryBudgetsCompanion(
                  id: Value(b['id'] as String),
                  categoryId: Value(b['categoryId'] as String),
                  year: Value((b['year'] as num).toInt()),
                  month: Value((b['month'] as num).toInt()),
                  amountMillimes: Value((b['amountMillimes'] as num).toInt()),
                ),
              );
        }
        for (final g in (decoded['savings_goals'] as List? ?? [])) {
          await db
              .into(db.savingsGoals)
              .insert(
                SavingsGoalsCompanion(
                  id: Value(g['id'] as String),
                  name: Value(g['name'] as String),
                  targetMillimes: Value((g['targetMillimes'] as num).toInt()),
                  targetDate: Value(
                    g['targetDate'] == null
                        ? null
                        : DateTime.parse(g['targetDate'] as String),
                  ),
                  walletId: Value(g['walletId'] as String?),
                  isArchived: Value((g['isArchived'] as bool?) ?? false),
                ),
              );
        }
        for (final c in (decoded['savings_contributions'] as List? ?? [])) {
          await db
              .into(db.savingsContributions)
              .insert(
                SavingsContributionsCompanion(
                  id: Value(c['id'] as String),
                  goalId: Value(c['goalId'] as String),
                  amountMillimes: Value((c['amountMillimes'] as num).toInt()),
                  occurredAt: Value(DateTime.parse(c['occurredAt'] as String)),
                  note: Value((c['note'] as String?) ?? ''),
                ),
              );
        }
        for (final d in (decoded['debts'] as List? ?? [])) {
          await db
              .into(db.debts)
              .insert(
                DebtsCompanion(
                  id: Value(d['id'] as String),
                  person: Value(d['person'] as String),
                  direction: Value(d['direction'] as String),
                  originalMillimes: Value(
                    (d['originalMillimes'] as num).toInt(),
                  ),
                  occurredAt: Value(DateTime.parse(d['occurredAt'] as String)),
                  dueDate: Value(
                    d['dueDate'] == null
                        ? null
                        : DateTime.parse(d['dueDate'] as String),
                  ),
                  notes: Value((d['notes'] as String?) ?? ''),
                  status: Value((d['status'] as String?) ?? 'open'),
                ),
              );
        }
        for (final p in (decoded['debt_payments'] as List? ?? [])) {
          await db
              .into(db.debtPayments)
              .insert(
                DebtPaymentsCompanion(
                  id: Value(p['id'] as String),
                  debtId: Value(p['debtId'] as String),
                  amountMillimes: Value((p['amountMillimes'] as num).toInt()),
                  walletId: Value(p['walletId'] as String),
                  txnId: Value(p['txnId'] as String?),
                  occurredAt: Value(DateTime.parse(p['occurredAt'] as String)),
                  note: Value((p['note'] as String?) ?? ''),
                ),
              );
        }
        // v1-v6 backups carry no templates → empty list (normalized).
        for (final t in (decoded['txn_templates'] as List? ?? [])) {
          await db
              .into(db.txnTemplates)
              .insert(
                TxnTemplatesCompanion(
                  id: Value(t['id'] as String),
                  name: Value(t['name'] as String),
                  type: Value(t['type'] as String),
                  amountMillimes: Value((t['amountMillimes'] as num).toInt()),
                  walletId: Value(t['walletId'] as String?),
                  toWalletId: Value(t['toWalletId'] as String?),
                  categoryId: Value(t['categoryId'] as String?),
                  note: Value((t['note'] as String?) ?? ''),
                  sortOrder: Value((t['sortOrder'] as num?)?.toInt() ?? 0),
                  createdAt: Value(
                    DateTime.parse(t['createdAt'] as String),
                  ),
                ),
              );
        }
        // v1-v7 backups carry no splits → empty list (normalized).
        for (final s in (decoded['txn_splits'] as List? ?? [])) {
          await db
              .into(db.txnSplits)
              .insert(
                TxnSplitsCompanion(
                  id: Value(s['id'] as String),
                  txnId: Value(s['txnId'] as String),
                  categoryId: Value(s['categoryId'] as String?),
                  amountMillimes: Value((s['amountMillimes'] as num).toInt()),
                  note: Value((s['note'] as String?) ?? ''),
                  createdAt: Value(
                    DateTime.parse(s['createdAt'] as String),
                  ),
                ),
              );
        }
      });
      // Refresh in-memory settings state.
      final settings = ref.read(settingsRepoProvider);
      ref.read(languageProvider.notifier).state = await settings.language();
      ref.read(themeNameProvider.notifier).state = await settings.theme();
      ref.read(onboardingDoneProvider.notifier).state = await settings
          .onboardingDone();
      bumpRefresh(ref);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportCsv() async {
    final lang = ref.read(languageProvider);
    setState(() => busy = true);
    try {
      final txns = await db.select(db.transactions).get();
      final wallets = await db.select(db.wallets).get();
      final cats = await db.select(db.categories).get();
      String wn(String id) =>
          wallets.where((w) => w.id == id).map((w) => w.name).firstOrNull ?? id;
      String cn(String? id) {
        if (id == null) return '';
        return cats
                .where((c) => c.id == id)
                .map((c) => Strings.categoryName(lang, c.nameKey, c.customName))
                .firstOrNull ??
            '';
      }

      final rows = [
        for (final t in txns)
          {
            'date': t.occurredAt.toIso8601String(),
            'type': t.type,
            'amount_millimes': t.amountMillimes,
            'amount_tnd': (t.amountMillimes / 1000).toStringAsFixed(3),
            'category': cn(t.categoryId),
            'wallet': wn(t.walletId),
            'to_wallet': t.toWalletId == null ? '' : wn(t.toWalletId!),
            'note': t.note,
          },
      ];
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/masroufi_export.csv');
      // BOM keeps Arabic readable in Excel.
      await f.writeAsString('\uFEFF${BackupCodec.buildCsv(rows)}');
      final uri = await FilePicker.saveFile(
        fileName: 'masroufi_export.csv',
        bytes: await f.readAsBytes(),
      );
      setState(() => msg = uri?.toString() ?? f.path);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// CSV IMPORT: pick → pure pre-validate → error-report dialog →
  /// confirmed insert of valid rows only. Unknown wallets (or transfer
  /// targets) reject the row; unknown categories fall back to
  /// uncategorized. Nothing commits before confirmation.
  Future<void> importCsv() async {
    final lang = ref.read(languageProvider);
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    final preview = BackupCodec.parseCsvImport(
      await File(path).readAsString(),
    );
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Strings.get(lang, 'importCsv')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                Strings.get(lang, 'csvBackupFirst'),
                style: Theme.of(c).textTheme.bodySmall?.copyWith(
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Strings.tpl(lang, 'csvSummary', {
                  'ok': '${preview.rows.length}',
                  'bad': '${preview.errors.length}',
                }),
              ),
              for (final e in preview.errors.take(10))
                Text(
                  'Row ${e.row}: ${e.message}',
                  style: Theme.of(c).textTheme.bodySmall?.copyWith(
                    color: Theme.of(c).colorScheme.error,
                  ),
                ),
              if (preview.errors.length > 10)
                Text(
                  '… +${preview.errors.length - 10}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Strings.get(lang, 'cancel')),
          ),
          FilledButton(
            onPressed: preview.rows.isEmpty
                ? null
                : () => Navigator.pop(c, true),
            child: Text(Strings.get(lang, 'importCsv')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final wallets = await ref.read(walletsRepoProvider).all();
      final cats = await ref.read(categoriesRepoProvider).all();
      String? walletId(String name) => wallets
          .where((w) => w.name.toLowerCase() == name.toLowerCase())
          .map((w) => w.id)
          .firstOrNull;
      String? catId(String? name) {
        if (name == null) return null;
        for (final c in cats) {
          if ((c.customName ?? '').toLowerCase() == name.toLowerCase()) {
            return c.id;
          }
          for (final l in ['en', 'fr', 'ar']) {
            if (Strings.categoryName(l, c.nameKey, null).toLowerCase() ==
                name.toLowerCase()) {
              return c.id;
            }
          }
        }
        return null;
      }

      final txns = ref.read(transactionsRepoProvider);
      var done = 0;
      var skipped = 0;
      // Session restore point (Track 3): every inserted row id is kept so
      // the whole import can be undone once. Backup-first is advised in
      // the preview dialog; undo is best-effort for this session only.
      final insertedIds = <String>[];
      for (final r in preview.rows) {
        final from = walletId(r.walletName);
        final to = r.toWalletName == null ? null : walletId(r.toWalletName!);
        if (from == null || (r.type == 'transfer' && to == null)) {
          skipped++;
          continue;
        }
        try {
          final id = await (() async {
            if (r.type == 'transfer') {
              if (from == to) throw StateError('self-transfer');
              return txns.addTransfer(
                amountMillimes: r.amountMillimes,
                fromWalletId: from,
                toWalletId: to!,
                when: r.occurredAt,
                note: r.note,
              );
            } else if (r.type == 'income') {
              return txns.addIncome(
                amountMillimes: r.amountMillimes,
                walletId: from,
                categoryId: catId(r.categoryName),
                when: r.occurredAt,
                note: r.note,
              );
            } else {
              return txns.addExpense(
                amountMillimes: r.amountMillimes,
                walletId: from,
                categoryId: catId(r.categoryName),
                when: r.occurredAt,
                note: r.note,
              );
            }
          })();
          insertedIds.add(id);
          done++;
        } catch (_) {
          skipped++;
        }
      }
      bumpRefresh(ref);
      setState(
        () => msg = Strings.tpl(lang, 'csvImported', {
          'ok': '$done',
          'bad': '${skipped + preview.errors.length}',
        }),
      );
      if (insertedIds.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Strings.tpl(lang, 'csvImported', {
                'ok': '$done',
                'bad': '${skipped + preview.errors.length}',
              }),
            ),
            action: SnackBarAction(
              label: Strings.get(lang, 'csvUndo'),
              onPressed: () async {
                for (final id in insertedIds) {
                  try {
                    await ref.read(transactionsRepoProvider).delete(id);
                  } catch (_) {}
                }
                bumpRefresh(ref);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(Strings.get(lang, 'csvUndone')),
                  ),
                );
              },
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'backup'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BackupNag(
            onBackup: createBackup,
          ),
          FutureBuilder(
            future: ref.watch(settingsRepoProvider).lastBackupAt(),
            builder: (context, snap) {
              final at = snap.data;
              final text = at == null
                  ? Strings.get(lang, 'noBackupYet')
                  : '${Strings.get(lang, 'lastBackup')}: '
                        '${at.toLocal().year}-'
                        '${at.toLocal().month.toString().padLeft(2, '0')}-'
                        '${at.toLocal().day.toString().padLeft(2, '0')} '
                        '${at.toLocal().hour.toString().padLeft(2, '0')}:'
                        '${at.toLocal().minute.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
          FilledButton(
            onPressed: busy ? null : createBackup,
            child: Text(Strings.get(lang, 'createBackup')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : restoreBackup,
            child: Text(Strings.get(lang, 'restoreBackup')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : exportCsv,
            child: Text(Strings.get(lang, 'exportCsv')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : importCsv,
            child: Text(Strings.get(lang, 'importCsv')),
          ),
          if (busy) ...[const SizedBox(height: 16), const LoadingView()],
          if (msg != null) ...[
            const SizedBox(height: 16),
            Text(msg!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Backup-health nag (Track 5): shows when the last backup is 14+ days
/// old (or never), dismissible via `backup_nag_dismissed_at` KV. Never
/// blocks; Backup Now jumps straight to a manual backup.
class _BackupNag extends ConsumerWidget {
  final Future<void> Function() onBackup;
  const _BackupNag({required this.onBackup});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return FutureBuilder(
      future: Future.wait([
        ref.watch(settingsRepoProvider).lastBackupAt(),
        ref.watch(settingsRepoProvider).get('backup_nag_dismissed_at'),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final at = snap.data![0] as DateTime?;
        final dismissedRaw = snap.data![1] as String?;
        DateTime? dismissed;
        try {
          dismissed = dismissedRaw == null
              ? null
              : DateTime.parse(dismissedRaw);
        } catch (_) {
          dismissed = null;
        }
        final now = DateTime.now();
        final stale = at == null || now.difference(at) >= const Duration(days: 14);
        if (!stale) return const SizedBox.shrink();
        if (dismissed != null &&
            at != null &&
            !dismissed.isBefore(at)) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Strings.get(lang, 'backupStale')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(settingsRepoProvider)
                            .set(
                              'backup_nag_dismissed_at',
                              now.toUtc().toIso8601String(),
                            );
                        if (context.mounted) {
                          (context as Element).markNeedsBuild();
                        }
                      },
                      child: Text(Strings.get(lang, 'dismiss')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: onBackup,
                      child: Text(Strings.get(lang, 'backupNow')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
