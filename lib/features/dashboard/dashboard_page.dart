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

class _DashData {
  final int total;
  final int income;
  final int expense;
  final List<Wallet> wallets;
  final Map<String, int> balances;
  final List<Transaction> recent;
  final Map<String?, int> byCat;
  final List<Category> cats;
  final Budget? budget;
  final int budgetSpent;
  _DashData({
    required this.total,
    required this.income,
    required this.expense,
    required this.wallets,
    required this.balances,
    required this.recent,
    required this.byCat,
    required this.cats,
    required this.budget,
    required this.budgetSpent,
  });
}

final _dashProvider = FutureProvider<_DashData>((ref) async {
  ref.watch(refreshTickProvider);
  final walletsRepo = ref.watch(walletsRepoProvider);
  final txns = ref.watch(transactionsRepoProvider);
  final catsRepo = ref.watch(categoriesRepoProvider);
  final budgets = ref.watch(budgetsRepoProvider);
  final now = DateTime.now();
  final wallets = await walletsRepo.all(includeArchived: false);
  final balances = <String, int>{};
  var total = 0;
  for (final w in wallets) {
    final b = await walletsRepo.balance(w);
    balances[w.id] = b;
    total += b;
  }
  final sums = await walletsRepo.db.monthSums(now.year, now.month);
  final recent = await txns.list(const TxnFilter(limit: 8));
  final byCat = await walletsRepo.db.expenseByCategory(now.year, now.month);
  final cats = await catsRepo.all();
  final budget = await budgets.getMonth(now.year, now.month);
  final spent = await budgets.spent(now.year, now.month);
  return _DashData(
    total: total,
    income: sums.income,
    expense: sums.expense,
    wallets: wallets,
    balances: balances,
    recent: recent,
    byCat: byCat,
    cats: cats,
    budget: budget,
    budgetSpent: spent,
  );
});

String _catName(String lang, List<Category> cats, String? id) {
  if (id == null) return '—';
  for (final c in cats) {
    if (c.id == id) return Strings.categoryName(lang, c.nameKey, c.customName);
  }
  return '—';
}

String _walletName(List<Wallet> wallets, String id, String? toId) {
  String n(String i) =>
      wallets.where((w) => w.id == i).map((w) => w.name).firstOrNull ?? '—';
  return toId == null ? n(id) : '${n(id)} → ${n(toId)}';
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final async = ref.watch(_dashProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'dashboard'))),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(_dashProvider),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(_dashProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _balanceCard(context, lang, d),
              const SizedBox(height: AppSpacing.md),
              _quickActions(context, lang),
              const SizedBox(height: AppSpacing.md),
              _monthRow(context, lang, d),
              if (d.budget != null) ...[
                const SizedBox(height: AppSpacing.md),
                _budgetCard(context, lang, d),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                Strings.get(lang, 'recent'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...d.recent.map(
                (t) => ListTile(
                  leading: Icon(
                    t.type == 'expense'
                        ? Icons.remove_circle
                        : t.type == 'income'
                        ? Icons.add_circle
                        : Icons.swap_horiz,
                    color: t.type == 'expense'
                        ? AppColors.expense
                        : t.type == 'income'
                        ? AppColors.income
                        : AppColors.transfer,
                  ),
                  title: Text(
                    t.note.isEmpty
                        ? _catName(lang, d.cats, t.categoryId)
                        : t.note,
                  ),
                  subtitle: Text(
                    _walletName(d.wallets, t.walletId, t.toWalletId),
                  ),
                  trailing: Text(
                    '${t.type == 'expense'
                        ? '−'
                        : t.type == 'income'
                        ? '+'
                        : '⇄'} ${Money.format(t.amountMillimes, lang: lang)}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  onTap: () => context.push('/add?edit=${t.id}&type=${t.type}'),
                ),
              ),
              if (d.recent.isEmpty)
                EmptyState(
                  title: Strings.get(lang, 'noTransactions'),
                  body: Strings.get(lang, 'noTransactionsBody'),
                  icon: Icons.receipt_long,
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                Strings.get(lang, 'topCategories'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ..._topCats(lang, d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(BuildContext context, String lang, _DashData d) {
    final maxBar =
        (d.byCat.values.isEmpty
                ? 0
                : d.byCat.values.reduce((a, b) => a > b ? a : b))
            .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.get(lang, 'totalBalance'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              Money.format(d.total, lang: lang),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (maxBar <= 0 && d.recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  Strings.get(lang, 'noTransactionsBody'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context, String lang) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: () => context.push('/add?type=expense'),
            icon: const Icon(Icons.remove, size: 28),
            label: Text(
              Strings.get(lang, 'expense'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.push('/add?type=income'),
            child: Text(Strings.get(lang, 'income')),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.push('/add?type=transfer'),
            child: Text(Strings.get(lang, 'transfer')),
          ),
        ),
      ],
    );
  }

  Widget _monthRow(BuildContext context, String lang, _DashData d) {
    return Row(
      children: [
        Expanded(
          child: _stat(
            context,
            Strings.get(lang, 'monthIncome'),
            d.income,
            lang,
            AppColors.income,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _stat(
            context,
            Strings.get(lang, 'monthExpenses'),
            d.expense,
            lang,
            AppColors.expense,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _stat(
            context,
            Strings.get(lang, 'remaining'),
            d.income - d.expense,
            lang,
            null,
          ),
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    int value,
    String lang,
    Color? color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              Money.format(value, lang: lang),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _budgetCard(BuildContext context, String lang, _DashData d) {
    final b = d.budget!;
    final pct = b.amountMillimes <= 0
        ? 0.0
        : (d.budgetSpent / b.amountMillimes).clamp(0.0, 1.0);
    final over = d.budgetSpent > b.amountMillimes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Strings.get(lang, 'budget'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${Money.format(d.budgetSpent, lang: lang)} / ${Money.format(b.amountMillimes, lang: lang)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              color: over ? Theme.of(context).colorScheme.error : null,
            ),
            const SizedBox(height: 4),
            Text(
              over
                  ? '⚠ ${(pct * 100).toStringAsFixed(0)}% ${Strings.get(lang, 'used')}'
                  : '${(pct * 100).toStringAsFixed(0)}% ${Strings.get(lang, 'used')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: over ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _topCats(String lang, _DashData d) {
    final entries = d.byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    if (top.isEmpty) return [];
    final maxV = top.first.value.toDouble();
    return [
      for (final e in top)
        Builder(
          builder: (context) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_catName(lang, d.cats, e.key))),
                      Text(
                        Money.format(e.value, lang: lang),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: maxV <= 0 ? 0 : e.value / maxV,
                    minHeight: 6,
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }
}
