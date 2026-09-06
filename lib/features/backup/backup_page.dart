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
    'createdAt': w.createdAt.toIso8601String(),
    'updatedAt': w.updatedAt.toIso8601String(),
  };

  Map<String, dynamic> _catJson(Category c) => {
    'id': c.id,
    'nameKey': c.nameKey,
    'customName': c.customName,
    'icon': c.icon,
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
        await db.delete(db.transactions).go();
        await db.delete(db.budgets).go();
        await db.delete(db.wallets).go();
        await db.delete(db.categories).go();
        await db.delete(db.appSettings).go();
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
                  isArchived: Value((c['isArchived'] as bool?) ?? false),
                  sortOrder: Value((c['sortOrder'] as num?)?.toInt() ?? 0),
                ),
              );
        }
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

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'backup'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
