import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/repositories/transactions_repo.dart';
import 'txn_sheets.dart';

final _typeFilter = StateProvider<String?>((ref) => null);
final walletFilterProvider = StateProvider<String?>((ref) => null);
// Public so dashboard top-category drill-down can preselect it.
final catFilterProvider = StateProvider<String?>((ref) => null);
final _searchQuery = StateProvider<String>((ref) => '');

/// Finance timeline (§14): day-grouped transaction tiles with full filters.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final type = ref.watch(_typeFilter);
    final walletId = ref.watch(walletFilterProvider);
    final catId = ref.watch(catFilterProvider);
    final search = ref.watch(_searchQuery);
    ref.watch(refreshTickProvider);
    final txnsRepo = ref.watch(transactionsRepoProvider);
    final walletsRepo = ref.watch(walletsRepoProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'history'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md2,
              AppSpacing.md,
              0,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: Strings.get(lang, 'search'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => ref.read(_searchQuery.notifier).state = v,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md2,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _chip(context, ref, Strings.get(lang, 'all'), type == null, () {
                  ref.read(_typeFilter.notifier).state = null;
                }),
                for (final t in ['expense', 'income', 'transfer'])
                  _chip(context, ref, Strings.get(lang, t), type == t, () {
                    ref.read(_typeFilter.notifier).state = t;
                  }),
              ],
            ),
          ),
          FutureBuilder(
            future: Future.wait([
              walletsRepo.all(includeArchived: true),
              catsRepo.all(includeArchived: true),
            ]),
            builder: (context, meta) {
              if (!meta.hasData) return const SizedBox.shrink();
              final wallets = meta.data![0] as List<Wallet>;
              final cats = meta.data![1] as List<Category>;
              final catById = {for (final c in cats) c.id: c};
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: walletId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: Strings.get(lang, 'filterWallet'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(Strings.get(lang, 'all')),
                          ),
                          for (final w in wallets)
                            DropdownMenuItem(value: w.id, child: Text(w.name)),
                        ],
                        onChanged: (v) =>
                            ref.read(walletFilterProvider.notifier).state = v,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: catId,
                        // Hierarchical labels ("Parent › Child") run long:
                        // expand so the value ellipsizes instead of
                        // overflowing the row.
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: Strings.get(lang, 'filterCategory'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(Strings.get(lang, 'all')),
                          ),
                          for (final c in cats)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                CategoryHierarchy.displayName(lang, c, catById),
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            ref.read(catFilterProvider.notifier).state = v,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: FutureBuilder(
              future: () async {
                // A parent filter rolls up: match parent + children.
                final allCats = await catsRepo.all(includeArchived: true);
                final ids = catId == null
                    ? null
                    : [
                        catId,
                        for (final c in allCats)
                          if (c.parentId == catId) c.id,
                      ];
                return Future.wait([
                  txnsRepo.list(
                    TxnFilter(
                      type: type,
                      walletId: walletId,
                      categoryIds: ids,
                      search: search.isEmpty ? null : search,
                      limit: 300,
                    ),
                  ),
                  walletsRepo.all(),
                  Future.value(allCats),
                ]);
              }(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return ErrorView(
                    message: '${snap.error}',
                    onRetry: () => bumpRefresh(ref),
                  );
                }
                final list = snap.data![0] as List<Transaction>;
                final wallets = snap.data![1] as List<Wallet>;
                final cats = snap.data![2] as List<Category>;
                final byId = {for (final c in cats) c.id: c};
                if (list.isEmpty) {
                  return EmptyState(
                    title: Strings.get(lang, 'noTransactions'),
                    body: Strings.get(lang, 'noTransactionsBody'),
                    icon: Icons.receipt_long,
                  );
                }
                final now = DateTime.now();
                // Group by day, newest first.
                final groups = <String, List<Transaction>>{};
                for (final t in list) {
                  final k =
                      '${t.occurredAt.year}-${t.occurredAt.month.toString().padLeft(2, '0')}-${t.occurredAt.day.toString().padLeft(2, '0')}';
                  (groups[k] ??= []).add(t);
                }
                String wn(String id, String? to) {
                  String n(String i) =>
                      wallets
                          .where((w) => w.id == i)
                          .map((w) => w.name)
                          .firstOrNull ??
                      '—';
                  return to == null ? n(id) : '${n(id)} → ${n(to)}';
                }

                String cn(String? id) {
                  if (id == null) return '—';
                  final c = byId[id];
                  if (c == null) return '—';
                  return CategoryHierarchy.displayName(lang, c, byId);
                }

                String? ci(String? id) {
                  if (id == null) return null;
                  return cats
                      .where((c) => c.id == id)
                      .map((c) => c.icon)
                      .firstOrNull;
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, gi) {
                    final key = groups.keys.elementAt(gi);
                    final items = groups[key]!;
                    final day = items.first.occurredAt;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.md,
                            bottom: AppSpacing.xs,
                          ),
                          child: Text(
                            '${relativeDay(day, now, lang)} • $key',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 1, indent: 68),
                              Builder(
                                builder: (context) {
                                  final t = items[i];
                                  final hier = t.categoryId == null
                                      ? null
                                      : cn(t.categoryId);
                                  final title = t.type == 'transfer'
                                      ? wn(t.walletId, t.toWalletId)
                                      : (t.note.isEmpty
                                            ? (hier ?? '—')
                                            : t.note);
                                  final time =
                                      '${t.occurredAt.hour.toString().padLeft(2, '0')}:'
                                      '${t.occurredAt.minute.toString().padLeft(2, '0')}';
                                  final sub =
                                      '${wn(t.walletId, t.toWalletId)} · $time';
                                  return Dismissible(
                                    key: ValueKey(t.id),
                                    background: Container(
                                      color: AppColors.expense,
                                    ),
                                    // Same instant-delete + undo contract as
                                    // the main timeline (no confirm dialog).
                                    onDismissed: (_) =>
                                        deleteTxnWithUndo(context, ref, t),
                                    child: TransactionTile(
                                      iconKey: t.type == 'transfer'
                                          ? 'transfer'
                                          : ci(t.categoryId),
                                      title: title,
                                      subtitle:
                                          (t.type != 'transfer' &&
                                              t.note.isNotEmpty &&
                                              hier != null &&
                                              hier != '—' &&
                                              hier != t.note)
                                          ? '$sub · $hier'
                                          : sub,
                                      millimes: t.amountMillimes,
                                      lang: lang,
                                      type: t.type,
                                      onTap: () => showTxnDetail(
                                        context,
                                        ref,
                                        t: t,
                                        wallets: wallets,
                                        cats: cats,
                                        lang: lang,
                                      ),
                                      onLongPress: () => showTxnMenu(
                                        context,
                                        ref,
                                        t: t,
                                        wallets: wallets,
                                        cats: cats,
                                        lang: lang,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    WidgetRef ref,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
