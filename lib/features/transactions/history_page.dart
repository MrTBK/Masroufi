import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/repositories/transactions_repo.dart';

final _typeFilter = StateProvider<String?>((ref) => null);
final _walletFilter = StateProvider<String?>((ref) => null);
final _catFilter = StateProvider<String?>((ref) => null);
final _searchQuery = StateProvider<String>((ref) => '');

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final type = ref.watch(_typeFilter);
    final walletId = ref.watch(_walletFilter);
    final catId = ref.watch(_catFilter);
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _chip(
                  context,
                  ref,
                  Strings.get(lang, 'all'),
                  type == null,
                  () => ref.read(_typeFilter.notifier).state = null,
                ),
                for (final t in ['expense', 'income', 'transfer'])
                  _chip(
                    context,
                    ref,
                    Strings.get(lang, t),
                    type == t,
                    () => ref.read(_typeFilter.notifier).state = t,
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: Future.wait([
                txnsRepo.list(
                  TxnFilter(
                    type: type,
                    walletId: walletId,
                    categoryId: catId,
                    search: search.isEmpty ? null : search,
                    limit: 300,
                  ),
                ),
                walletsRepo.all(),
                catsRepo.all(),
              ]),
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
                if (list.isEmpty) {
                  return EmptyState(
                    title: Strings.get(lang, 'noTransactions'),
                    body: Strings.get(lang, 'noTransactionsBody'),
                    icon: Icons.receipt_long,
                  );
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
                  return cats
                          .where((c) => c.id == id)
                          .map(
                            (c) => Strings.categoryName(
                              lang,
                              c.nameKey,
                              c.customName,
                            ),
                          )
                          .firstOrNull ??
                      '—';
                }

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return Dismissible(
                      key: ValueKey(t.id),
                      background: Container(color: AppColors.expense),
                      confirmDismiss: (_) async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(Strings.get(lang, 'confirmDelete')),
                            content: Text(
                              Strings.get(lang, 'confirmDeleteBody'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(Strings.get(lang, 'cancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(Strings.get(lang, 'delete')),
                              ),
                            ],
                          ),
                        );
                        return ok == true;
                      },
                      onDismissed: (_) async {
                        await txnsRepo.delete(t.id);
                        bumpRefresh(ref);
                      },
                      child: ListTile(
                        leading: Icon(
                          t.type == 'expense'
                              ? Icons.remove_circle
                              : t.type == 'income'
                              ? Icons.add_circle
                              : Icons.swap_horiz,
                        ),
                        title: Text(t.note.isEmpty ? cn(t.categoryId) : t.note),
                        subtitle: Text(
                          '${wn(t.walletId, t.toWalletId)} • ${t.occurredAt.year}-${t.occurredAt.month.toString().padLeft(2, '0')}-${t.occurredAt.day.toString().padLeft(2, '0')}',
                        ),
                        trailing: Text(
                          Money.format(t.amountMillimes, lang: lang),
                        ),
                        onTap: () =>
                            context.push('/add?edit=${t.id}&type=${t.type}'),
                        onLongPress: () async {
                          await txnsRepo.duplicate(t.id);
                          bumpRefresh(ref);
                        },
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
