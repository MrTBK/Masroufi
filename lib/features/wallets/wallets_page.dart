import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/repositories/transactions_repo.dart';

class WalletsPage extends ConsumerWidget {
  const WalletsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(walletsRepoProvider);
    final txns = ref.watch(transactionsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'wallets'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _walletDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: repo.watch(includeArchived: true),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final wallets = snap.data!;
          if (wallets.isEmpty) {
            return EmptyState(
              title: Strings.get(lang, 'wallets'),
              body: '',
              icon: Icons.wallet,
            );
          }
          return ListView.builder(
            itemCount: wallets.length,
            itemBuilder: (context, i) {
              final w = wallets[i];
              return FutureBuilder<int>(
                future: repo.balance(w),
                builder: (context, b) => ListTile(
                  leading: Icon(appIcon(w.icon)),
                  title: Text(w.name),
                  subtitle: Text(
                    w.isArchived
                        ? Strings.get(lang, 'archived')
                        : Strings.get(lang, 'active'),
                  ),
                  trailing: Text(
                    Money.format(b.data ?? 0, lang: lang),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  onTap: () => _walletDialog(context, ref, w),
                  onLongPress: () => _walletTxns(context, ref, txns, lang, w),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _walletDialog(
    BuildContext context,
    WidgetRef ref,
    Wallet? w,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(walletsRepoProvider);
    final nameCtl = TextEditingController(text: w?.name ?? '');
    final balCtl = TextEditingController(
      text: w == null
          ? '0'
          : ((await repo.balance(w)) / 1000).toStringAsFixed(3),
    );
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          w == null
              ? Strings.get(lang, 'newWallet')
              : Strings.get(lang, 'edit'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(
                labelText: Strings.get(lang, 'walletName'),
              ),
            ),
            const SizedBox(height: 8),
            if (w == null)
              TextField(
                controller: balCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'initialBalance'),
                ),
              ),
          ],
        ),
        actions: [
          if (w != null)
            TextButton(
              onPressed: () async {
                await repo.setArchived(w.id, !w.isArchived);
                bumpRefresh(ref);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(
                Strings.get(lang, w.isArchived ? 'unarchive' : 'archive'),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(Strings.get(lang, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              if (w == null) {
                int initial = 0;
                try {
                  initial = Money.parse(balCtl.text);
                } catch (_) {
                  return;
                }
                await repo.create(name: name, initialMillimes: initial);
              } else {
                await repo.rename(w.id, name);
              }
              bumpRefresh(ref);
              if (c.mounted) Navigator.pop(c);
            },
            child: Text(Strings.get(lang, 'save')),
          ),
        ],
      ),
    );
  }

  Future<void> _walletTxns(
    BuildContext context,
    WidgetRef ref,
    TransactionsRepo txnsRepo,
    String lang,
    Wallet w,
  ) async {
    final list = await txnsRepo.list(TxnFilter(walletId: w.id, limit: 200));
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(w.name),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final t in list)
                ListTile(
                  title: Text(t.note.isEmpty ? t.type : t.note),
                  trailing: Text(Money.format(t.amountMillimes, lang: lang)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(Strings.get(lang, 'cancel')),
          ),
        ],
      ),
    );
  }
}
