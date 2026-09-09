import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/analytics/periods.dart';
import '../../core/analytics/summary.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/masroufi_nav.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/repositories/transactions_repo.dart';
import 'filter_sheet.dart';
import 'history_page.dart' show catFilterProvider, walletFilterProvider;
import 'txn_sheets.dart';

// Public so the filter sheet shares them.
final txnTypeFilterProvider = StateProvider<String?>((ref) => null);
final txnSearchProvider = StateProvider<String>((ref) => '');
final txnLimitProvider = StateProvider<int>((ref) => 300);

/// Optional timeline date window (null = all time). Set by the filter
/// sheet presets/custom range; half-open [from, to).
final txnDateRangeProvider =
    StateProvider<({DateTime from, DateTime to})?>((ref) => null);

/// Which date chip the range came from (today/week/month/custom/null).
/// Display-only: the range above is the source of truth.
final txnDatePresetProvider = StateProvider<String?>((ref) => null);

/// Comparison strip ids (INFORMATION, not navigation): computed with the
/// same tested `Periods.txnRangeFor` bounds the old chips used.
const _comparePeriods = [
  'today',
  'yesterday',
  'thisWeek',
  'lastWeek',
  'thisMonth',
  'lastMonth',
];

/// TRANSACTIONS — the financial home (brief §1-4, §10, §34-35).
/// Always Today-first: today's spending → your money → compact period
/// comparison (information, never navigation) → today's transactions,
/// then older days on scroll. All sums come from the existing repos.
class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // Plain brand identity: on the main page the title is NOT a button
      // (no accidental-clickable look). The logo mark makes it a header.
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.account_balance_wallet,
                size: 20,
                color: scheme.onPrimaryContainer,
                semanticLabel: Brand.nameFor(lang),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(Brand.nameFor(lang)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: Strings.get(lang, 'settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: HomeTopSwitch(
              showTransactions: true,
              lang: lang,
              onTransactions: () {},
              onDashboard: () => context.go('/dashboard'),
              onSettings: () => context.push('/settings'),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => bumpRefresh(ref),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _TodayHero(lang: lang),
                  const SizedBox(height: AppSpacing.md),
                  _Comparisons(lang: lang),
                  const SizedBox(height: AppSpacing.md),
                  _FilterButton(lang: lang),
                  const SizedBox(height: AppSpacing.xs),
                  _Timeline(lang: lang),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TODAY hero: label → spent (big) → your money + global eye →
/// expandable per-wallet breakdown → daily budget guidance (when a
/// monthly budget exists). Hidden wallets are EXCLUDED from the total
/// (display-level exclusion, see `WalletsRepo.visibleBalance`); only
/// the global switch masks.
class _TodayHero extends ConsumerStatefulWidget {
  final String lang;
  const _TodayHero({required this.lang});

  @override
  ConsumerState<_TodayHero> createState() => _TodayHeroState();
}

class _TodayHeroState extends ConsumerState<_TodayHero> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final now = DateTime.now();
    final today = Periods.day(now);
    final analytics = ref.watch(analyticsRepoProvider);
    final walletsRepo = ref.watch(walletsRepoProvider);
    final budgetsRepo = ref.watch(budgetsRepoProvider);
    return FutureBuilder(
      future: () async {
        final spent = await analytics.expenseTotal(today.start, today.end);
        final total = await walletsRepo.visibleBalance();
        final wallets = await walletsRepo.all(includeArchived: false);
        final balances = <String, int>{};
        for (final w in wallets) {
          balances[w.id] = await walletsRepo.balance(w);
        }
        final budget = await budgetsRepo.getMonth(now.year, now.month);
        return (
          spent: spent,
          total: total,
          wallets: wallets,
          balances: balances,
          budget: budget?.amountMillimes,
        );
      }(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final d = snap.data!;
        final hideAll = ref.watch(hideBalancesProvider);
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.get(lang, 'today'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              Strings.get(lang, 'spent'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            MoneyText(
              millimes: d.spent,
              lang: lang,
              type: 'expense',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Strings.get(lang, 'yourMoney'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: VisibilityToggle(
                    hidden: hideAll,
                    hideLabel: Strings.get(lang, 'hideBalance'),
                    showLabel: Strings.get(lang, 'showBalance'),
                    onChanged: (v) async {
                      await ref.read(settingsRepoProvider).setHideBalances(v);
                      ref.read(hideBalancesProvider.notifier).state = v;
                    },
                  ),
                ),
              ],
            ),
            hideAll
                ? HiddenBalance(
                    semanticLabel: Strings.get(lang, 'hiddenBalance'),
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  )
                : MoneyText(
                    millimes: d.total,
                    lang: lang,
                    type: 'neutral',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
            // Expandable per-wallet breakdown (hidden wallets render
            // masked: visible proof they exist, zero balance leaked).
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${Strings.get(lang, 'wallets')} (${d.wallets.length})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: Strings.get(lang, 'wallets'),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              for (final w in d.wallets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          w.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      (hideAll || w.isBalanceHidden)
                          ? HiddenBalance(
                              semanticLabel: Strings.get(
                                lang,
                                'hiddenBalance',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          : MoneyText(
                              millimes: d.balances[w.id] ?? 0,
                              lang: lang,
                              type: 'neutral',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                    ],
                  ),
                ),
            if (d.budget != null && !hideAll)
              _dailyGuidance(context, lang, d.spent, d.budget!, now),
            const Divider(height: 24),
          ],
        );
      },
    );
  }

  /// Daily spending guidance: today's spend vs the suggested daily
  /// target (remaining budget ÷ days left, incl. today). Over budget
  /// shows the warning state instead of a target.
  Widget _dailyGuidance(
    BuildContext context,
    String lang,
    int todaySpent,
    int budget,
    DateTime now,
  ) {
    final g = dailyGuidance(
      budgetMillimes: budget,
      spentMillimes: todaySpent,
      now: now,
    );
    final scheme = Theme.of(context).colorScheme;
    if (g.remaining < 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 18, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                Strings.get(lang, 'overBudget'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            MoneyText(
              millimes: g.remaining,
              lang: lang,
              type: 'neutral',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    final frac = g.suggested <= 0
        ? 0.0
        : (todaySpent / g.suggested).clamp(0.0, 1.0);
    final over = g.suggested > 0 && todaySpent > g.suggested;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Strings.get(lang, 'suggestedDaily')} '
            '${Money.inline(g.suggested, lang: lang)} · '
            '${g.daysLeft} ${Strings.get(lang, 'daysLeft')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              color: over ? AppColors.expense : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact comparison strip: six expense totals as TYPOGRAPHY, not cards
/// and not buttons. One batched read; static labels in fixed order.
class _Comparisons extends ConsumerWidget {
  final String lang;
  const _Comparisons({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(weekStartProvider);
    final analytics = ref.watch(analyticsRepoProvider);
    final now = DateTime.now();
    return FutureBuilder(
      future: Future.wait([
        for (final p in _comparePeriods)
          (() {
            final r = Periods.txnRangeFor(p, now, weekStart);
            return analytics.expenseTotal(r.start, r.end);
          })(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final values = snap.data!;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 56,
          ),
          itemCount: _comparePeriods.length,
          itemBuilder: (context, i) {
            final v = values[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  Strings.get(lang, _comparePeriods[i]),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                MoneyText(
                  millimes: v,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Single filter entry point with an active-count badge. The sheet holds
/// search + type + wallet + category; the page stays unbothered.
class _FilterButton extends ConsumerWidget {
  final String lang;
  const _FilterButton({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = activeFilterCount(
      type: ref.watch(txnTypeFilterProvider),
      walletId: ref.watch(walletFilterProvider),
      catId: ref.watch(catFilterProvider),
      search: ref.watch(txnSearchProvider),
      hasDateRange: ref.watch(txnDateRangeProvider) != null,
    );
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => showFilterSheet(context, ref),
          icon: const Icon(Icons.filter_list, size: 20),
          label: Text(
            count > 0
                ? '${Strings.get(lang, 'filters')} ($count)'
                : Strings.get(lang, 'filters'),
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: () {
              ref.read(txnTypeFilterProvider.notifier).state = null;
              ref.read(walletFilterProvider.notifier).state = null;
              ref.read(catFilterProvider.notifier).state = null;
              ref.read(txnSearchProvider.notifier).state = '';
              ref.read(txnDateRangeProvider.notifier).state = null;
              ref.read(txnDatePresetProvider.notifier).state = null;
            },
            child: Text(Strings.get(lang, 'clearFilters')),
          ),
        ],
      ],
    );
  }
}

class _Timeline extends ConsumerWidget {
  final String lang;
  const _Timeline({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(txnTypeFilterProvider);
    final walletId = ref.watch(walletFilterProvider);
    final catId = ref.watch(catFilterProvider);
    final search = ref.watch(txnSearchProvider);
    final dateRange = ref.watch(txnDateRangeProvider);
    final limit = ref.watch(txnLimitProvider);
    final txnsRepo = ref.watch(transactionsRepoProvider);
    final walletsRepo = ref.watch(walletsRepoProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);
    // No period gate: Today-first ordering shows today on top, older days
    // follow on scroll. Filters narrow; limit pages with "show more".
    return FutureBuilder(
      future: () async {
        final allCats = await catsRepo.all(includeArchived: true);
        final wallets = await walletsRepo.all();
        // Explicit sheet selections win; otherwise the search box also
        // matches category/wallet NAMES (resolved here — the tables are
        // already in hand, so no JOINs in the hot query). Note/amount
        // matching stays inside TxnFilter.search.
        List<String>? nameCatIds;
        List<String>? nameWalletIds;
        if (search.isNotEmpty) {
          final q = search.toLowerCase();
          final matchedParents = <String>{
            for (final c in allCats)
              if (Strings.categoryName(
                lang,
                c.nameKey,
                c.customName,
              ).toLowerCase().contains(q))
                c.id,
          };
          nameCatIds = [
            for (final c in allCats)
              if (matchedParents.contains(c.id) ||
                  (c.parentId != null &&
                      matchedParents.contains(c.parentId)))
                c.id,
          ];
          nameWalletIds = [
            for (final w in wallets)
              if (w.name.toLowerCase().contains(q)) w.id,
          ];
        }
        final ids = catId == null
            ? (nameCatIds == null || nameCatIds.isEmpty ? null : nameCatIds)
            : [
                catId,
                for (final c in allCats)
                  if (c.parentId == catId) c.id,
              ];
        final wids = walletId == null
            ? (nameWalletIds == null || nameWalletIds.isEmpty
                  ? null
                  : nameWalletIds)
            : [walletId];
        return Future.wait([
          txnsRepo.list(
            TxnFilter(
              type: type,
              walletIds: wids,
              categoryIds: ids,
              search: search.isEmpty ? null : search,
              from: dateRange?.from,
              to: dateRange?.to,
              limit: limit,
            ),
          ),
          Future.value(wallets),
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
            actionLabel: Strings.get(lang, 'addExpense'),
            onAction: () => context.push('/add?type=expense'),
          );
        }
        final now = DateTime.now();
        final groups = <String, List<Transaction>>{};
        for (final t in list) {
          final k =
              '${t.occurredAt.year}-${t.occurredAt.month.toString().padLeft(2, '0')}-${t.occurredAt.day.toString().padLeft(2, '0')}';
          (groups[k] ??= []).add(t);
        }
        // Locale-aware transfer connector (mirrored arrow in Arabic).
        final arrow = lang == 'ar' ? '←' : '→';
        String wn(String id, String? to) {
          String n(String i) =>
              wallets.where((w) => w.id == i).map((w) => w.name).firstOrNull ??
              '—';
          return to == null ? n(id) : '${n(id)} $arrow ${n(to)}';
        }

        String cn(String? id) {
          if (id == null) return Strings.get(lang, 'uncategorized');
          final c = byId[id];
          if (c == null) return '—';
          return Strings.categoryName(lang, c.nameKey, c.customName);
        }

        String? ci(String? id) {
          if (id == null) return null;
          return byId[id]?.icon;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final key in groups.keys) ...[
              Builder(
                builder: (context) {
                  final items = groups[key]!;
                  final day = items.first.occurredAt;
                  // Client-side day total (sums exactly the rendered,
                  // filter-consistent rows — no extra query, no lag).
                  final dayExpense = items
                      .where((t) => t.type == 'expense')
                      .fold(0, (a, t) => a + t.amountMillimes);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.md,
                          bottom: AppSpacing.xs,
                        ),
                        child: Text(
                          dayGroupHeader(day, now, lang),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 68),
                        Builder(
                          builder: (context) {
                            final t = items[i];
                            final hier = t.categoryId == null
                                ? null
                                : cn(t.categoryId);
                            final title = txnTitle(lang, t, wallets, byId);
                            final sub =
                                '${wn(t.walletId, t.toWalletId)} · ${txnTime(t.occurredAt)}';
                            return Dismissible(
                              key: ValueKey(t.id),
                              background: Container(color: AppColors.expense),
                              // No confirm dialog: immediate delete with a
                              // 10s undo snackbar (destructive RESTORE
                              // keeps its confirmation).
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
                      if (dayExpense > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  Strings.get(lang, 'dayTotal'),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                              MoneyText(
                                millimes: dayExpense,
                                lang: lang,
                                type: 'neutral',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            // Page through history without loading the whole ledger at once.
            if (list.length >= limit)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () =>
                        ref.read(txnLimitProvider.notifier).state = limit + 300,
                    child: Text(Strings.get(lang, 'loadMore')),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
