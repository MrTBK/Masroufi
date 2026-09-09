import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config/brand.dart';
import '../../core/icons/category_icons.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/security/hidden_gate.dart';
import '../../core/theme/wallet_styles.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/masroufi_nav.dart';
import '../../core/widgets/wallet_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/repositories/transactions_repo.dart';

/// Wallet cards (spec §15-17): each wallet renders as a Masroufi card
/// with name, balance (or mask), icon and eye toggle.
/// Hidden ≠ archived: hiding masks display only (math untouched);
/// archiving removes the wallet from active use.
class WalletsPage extends ConsumerWidget {
  const WalletsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(walletsRepoProvider);
    final txns = ref.watch(transactionsRepoProvider);
    return Scaffold(
      appBar: AppBar(
        title: HomeTitle(
          text: '${Brand.nameFor(lang)} • ${Strings.get(lang, 'wallets')}',
          lang: lang,
        ),
        actions: [
          IconButton(
            tooltip: Strings.get(lang, 'settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        tooltip: Strings.get(lang, 'addWallet'),
        onPressed: () => _walletDialog(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(Strings.get(lang, 'addWallet')),
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: wallets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final w = wallets[i];
              return FutureBuilder<int>(
                future: repo.balance(w),
                builder: (context, b) {
                  final hideAll = ref.watch(hideBalancesProvider);
                  final masked = hideAll || w.isBalanceHidden;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WalletCardView(
                        name: w.name,
                        iconKey: w.icon,
                        colorKey: w.colorKey,
                        design: w.design,
                        balanceMillimes: b.data ?? 0,
                        masked: masked,
                        lang: lang,
                        hidden: w.isBalanceHidden,
                        sublabel: w.isArchived
                            ? Strings.get(lang, 'archived')
                            : Brand.nameFor(lang),
                        onTap: () => _walletDialog(context, ref, w),
                        onToggleHidden: (v) async {
                          // Track 8 per-action gate: revealing a hidden
                          // balance challenges via the lock stack.
                          if (!v) {
                            final ok =
                                await HiddenGate.ensureUnlocked(
                                  context,
                                  ref,
                                  revealsHidden: true,
                                );
                            if (!ok) return;
                          }
                          await repo.setBalanceHidden(w.id, v);
                          bumpRefresh(ref);
                        },
                      ),
                      if (!w.isArchived)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () =>
                                _walletTxns(context, ref, txns, lang, w),
                            child: Text(Strings.get(lang, 'history')),
                          ),
                        ),
                    ],
                  );
                },
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
    var icon = w?.icon ?? 'cash';
    var colorKey = w?.colorKey ?? 'teal';
    var design = w?.design ?? 'classic';
    if (!context.mounted) return;
    const walletIcons = ['cash', 'bank', 'card', 'savings', 'other'];
    final validIcon = CategoryIcons.isKnown(icon) ? icon : 'cash';
    icon = validIcon;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(
            w == null
                ? Strings.get(lang, 'addWallet')
                : Strings.get(lang, 'edit'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'walletName'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Strings.get(lang, 'pickIcon'),
                  style: Theme.of(c).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                IconPickerGrid(
                  keys: walletIcons,
                  selected: icon,
                  onSelected: (k) => setS(() => icon = k),
                ),
                const SizedBox(height: 8),
                Text(
                  Strings.get(lang, 'walletColor'),
                  style: Theme.of(c).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                WalletColorPicker(
                  selected: colorKey,
                  onSelected: (k) => setS(() => colorKey = k),
                ),
                const SizedBox(height: 8),
                Text(
                  Strings.get(lang, 'walletStyle'),
                  style: Theme.of(c).textTheme.titleSmall,
                ),
                DropdownButtonFormField<String>(
                  initialValue: design,
                  isExpanded: true,
                  items: [
                    for (final d in WalletStyles.designs)
                      DropdownMenuItem(value: d, child: Text(d)),
                  ],
                  onChanged: (v) => setS(() => design = v ?? 'classic'),
                ),
                if (w == null) ...[
                  const SizedBox(height: 8),
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
                const SizedBox(height: 4),
                Text(
                  Strings.get(lang, 'hiddenNote'),
                  style: Theme.of(c).textTheme.bodySmall?.copyWith(
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
                  final t = balCtl.text.trim();
                  if (t.isNotEmpty && !RegExp(r'^[0\s.,]+$').hasMatch(t)) {
                    try {
                      initial = Money.parse(t);
                    } catch (_) {
                      return;
                    }
                  }
                  await repo.create(
                    name: name,
                    icon: icon,
                    initialMillimes: initial,
                    colorKey: colorKey,
                    design: design,
                  );
                } else {
                  await repo.rename(w.id, name);
                  await repo.setIcon(w.id, icon);
                  await repo.setColorKey(w.id, colorKey);
                  await repo.setDesign(w.id, design);
                }
                bumpRefresh(ref);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(Strings.get(lang, 'save')),
            ),
          ],
        ),
      ),
    );
  }

  /// Wallet statistics sheet (§20): balance, this month in/out,
  /// transaction count, recent transactions. All values come from the
  /// existing repos (`WalletsRepo.balance`, `AnalyticsRepo.walletStats`).
  Future<void> _walletTxns(
    BuildContext context,
    WidgetRef ref,
    TransactionsRepo txnsRepo,
    String lang,
    Wallet w,
  ) async {
    final analytics = ref.read(analyticsRepoProvider);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final results = await Future.wait([
      ref.read(walletsRepoProvider).balance(w),
      analytics.walletStats(w.id, monthStart, monthEnd),
      txnsRepo.list(TxnFilter(walletId: w.id, limit: 5)),
    ]);
    if (!context.mounted) return;
    final balance = results[0] as int;
    final stats =
        results[1] as ({int income, int expense, int tIn, int tOut, int count});
    final recent = results[2] as List<Transaction>;
    final masked =
        ref.read(hideBalancesProvider) || w.isBalanceHidden;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                w.name,
                style: Theme.of(c).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Strings.get(lang, 'totalBalance'),
                style: Theme.of(c).textTheme.bodySmall,
              ),
              masked
                  ? HiddenBalance(
                      semanticLabel: Strings.get(lang, 'hiddenBalance'),
                      style: Theme.of(c).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : MoneyText(
                      millimes: balance,
                      lang: lang,
                      type: 'neutral',
                      style: Theme.of(c).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      c,
                      Strings.get(lang, 'moneyIn'),
                      stats.income + stats.tIn,
                      lang,
                      'income',
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      c,
                      Strings.get(lang, 'moneyOut'),
                      stats.expense + stats.tOut,
                      lang,
                      'expense',
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Strings.get(lang, 'transactions'),
                          style: Theme.of(c).textTheme.bodySmall,
                        ),
                        Text(
                          '${stats.count}',
                          style: Theme.of(c).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.note.isEmpty ? t.type : t.note),
                        trailing: MoneyText(
                          millimes: t.amountMillimes,
                          lang: lang,
                          type: t.type,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    int value,
    String lang,
    String type,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        MoneyText(
          millimes: value,
          lang: lang,
          type: type,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
