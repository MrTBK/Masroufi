import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';

/// How long a deleted transaction stays restorable (single-level undo:
/// each new delete replaces the pending snackbar).
const undoWindow = Duration(seconds: 10);

/// Shared timeline label helpers (single source; the timeline and the
/// detail/menu sheets all render identical titles).
String txnWalletLabel(
  List<Wallet> wallets,
  String lang,
  String id,
  String? toId,
) {
  String n(String i) =>
      wallets.where((w) => w.id == i).map((w) => w.name).firstOrNull ?? '—';
  if (toId == null) return n(id);
  // Mirrored connector in Arabic (direction carries meaning).
  return lang == 'ar' ? '${n(id)} ← ${n(toId)}' : '${n(id)} → ${n(toId)}';
}

/// Leaf category name (never "Parent › Child" on transactions — hierarchy
/// lives in management/filtering/analytics, per spec).
String txnCategoryName(String lang, Map<String, Category> byId, String? id) {
  if (id == null) return Strings.get(lang, 'uncategorized');
  final c = byId[id];
  if (c == null) return '—';
  return Strings.categoryName(lang, c.nameKey, c.customName);
}

String? txnIconKey(Map<String, Category> byId, String? id) =>
    id == null ? null : byId[id]?.icon;

String txnTitle(
  String lang,
  Transaction t,
  List<Wallet> wallets,
  Map<String, Category> byId,
) {
  if (t.type == 'transfer') return txnWalletLabel(wallets, lang, t.walletId, t.toWalletId);
  final hier = txnCategoryName(lang, byId, t.categoryId);
  return t.note.isEmpty ? hier : t.note;
}

String txnTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';

/// Immediate delete + Snackbar undo (replaces the old per-delete confirm
/// dialog; destructive RESTORE keeps its confirmation). Restores the
/// byte-identical row via `TransactionsRepo.restore`.
Future<void> deleteTxnWithUndo(
  BuildContext context,
  WidgetRef ref,
  Transaction t,
) async {
  final lang = ref.read(languageProvider);
  final repo = ref.read(transactionsRepoProvider);
  await repo.delete(t.id);
  bumpRefresh(ref);
  Haptics.confirm();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(Strings.get(lang, 'deletedTxn')),
      duration: undoWindow,
      action: SnackBarAction(
        label: Strings.get(lang, 'undo'),
        onPressed: () async {
          await repo.restore(t);
          bumpRefresh(ref);
        },
      ),
    ),
  );
}

/// Read-only detail sheet (§15): icon, name, amount, day/time, wallet,
/// category, note + Edit entry. The single place a tap lands.
Future<void> showTxnDetail(
  BuildContext context,
  WidgetRef ref, {
  required Transaction t,
  required List<Wallet> wallets,
  required List<Category> cats,
  required String lang,
}) {
  final byId = {for (final c in cats) c.id: c};
  final now = DateTime.now();
  final title = txnTitle(lang, t, wallets, byId);
  final day = relativeDay(t.occurredAt, now, lang);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        // Scrollable: small screens must never clip the sheet (§52).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            CategoryAvatar(
              iconKey: t.type == 'transfer'
                  ? 'transfer'
                  : txnIconKey(byId, t.categoryId),
              radius: 30,
              semanticLabel: title,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(c).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: MoneyText(
                millimes: t.amountMillimes,
                lang: lang,
                type: t.type,
                style: Theme.of(c).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$day · ${txnTime(t.occurredAt)}',
              textAlign: TextAlign.center,
              style: Theme.of(c).textTheme.bodySmall?.copyWith(
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            _kv(
              c,
              Strings.get(lang, 'wallet'),
              txnWalletLabel(wallets, lang, t.walletId, t.toWalletId),
            ),
            if (t.type != 'transfer')
              _kv(
                c,
                Strings.get(lang, 'category'),
                t.categoryId == null
                    ? Strings.get(lang, 'uncategorized')
                    : CategoryHierarchy.displayName(
                        lang,
                        byId[t.categoryId]!,
                        byId,
                      ),
              ),
            if (t.note.isNotEmpty)
              _kv(c, Strings.get(lang, 'note'), t.note),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/add?edit=${t.id}&type=${t.type}');
                    },
                    icon: const Icon(Icons.edit, size: 20),
                    label: Text(Strings.get(lang, 'edit')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await saveTxnAsTemplate(context, ref, t);
                      if (c.mounted && ok) Navigator.pop(c);
                    },
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    label: Text(Strings.get(lang, 'saveAsTemplate')),
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _kv(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      ),
    );
  }

/// Long-press menu (§17): edit / duplicate / copy / delete. Fast,
/// self-explanatory, no hidden gestures beyond this sheet.
Future<void> showTxnMenu(
  BuildContext context,
  WidgetRef ref, {
  required Transaction t,
  required List<Wallet> wallets,
  required List<Category> cats,
  required String lang,
}) {
  final byId = {for (final c in cats) c.id: c};
  final title = txnTitle(lang, t, wallets, byId);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(Strings.get(lang, 'edit')),
            onTap: () {
              Navigator.pop(c);
              context.push('/add?edit=${t.id}&type=${t.type}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all),
            title: Text(Strings.get(lang, 'duplicate')),
            onTap: () async {
              Navigator.pop(c);
              await ref.read(transactionsRepoProvider).duplicate(t.id);
              bumpRefresh(ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: Text(Strings.get(lang, 'copy')),
            onTap: () async {
              Navigator.pop(c);
              final sign = t.type == 'expense'
                  ? '-'
                  : t.type == 'income'
                  ? '+'
                  : '';
              await Clipboard.setData(
                ClipboardData(
                  text:
                      '$title · '
                      '${txnWalletLabel(wallets, lang, t.walletId, t.toWalletId)} · '
                      '$sign${Money.format(t.amountMillimes, lang: lang)}',
                ),
              );
              Haptics.select();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(Strings.get(lang, 'copied')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete,
              color: Theme.of(c).colorScheme.error,
            ),
            title: Text(
              Strings.get(lang, 'delete'),
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
            onTap: () {
              Navigator.pop(c);
              deleteTxnWithUndo(context, ref, t);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

/// Creates a template from a transaction (name = note, else category,
/// else type). Returns true when stored (caller closes + confirms).
Future<bool> saveTxnAsTemplate(
  BuildContext context,
  WidgetRef ref,
  Transaction t,
) async {
  final lang = ref.read(languageProvider);
  String name = t.note.trim();
  if (name.isEmpty && t.categoryId != null) {
    final cats = await ref.read(categoriesRepoProvider).all();
    final cat = cats.where((c) => c.id == t.categoryId).firstOrNull;
    if (cat != null) {
      name = Strings.categoryName(lang, cat.nameKey, cat.customName);
    }
  }
  name = name.isEmpty ? Strings.get(lang, t.type) : name;
  try {
    await ref
        .read(templatesRepoProvider)
        .create(
          name: name,
          type: t.type,
          amountMillimes: t.amountMillimes,
          walletId: t.walletId,
          toWalletId: t.toWalletId,
          categoryId: t.type == 'transfer' ? null : t.categoryId,
          note: t.note,
        );
  } catch (_) {
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Strings.get(lang, 'templateSaved')),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  return true;
}
