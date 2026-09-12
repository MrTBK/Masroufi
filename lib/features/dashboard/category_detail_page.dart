import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/repositories/transactions_repo.dart';
import 'dashboard_page.dart' show dashRangeFor;

/// Parent-category breakdown for the active dashboard period:
/// parent total, one row per subcategory, then recent transactions
/// in the whole subtree. Reached by tapping a spending row.
class CategoryDetailPage extends ConsumerWidget {
  final String categoryId;
  const CategoryDetailPage({super.key, required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final period = ref.watch(dashPeriodProvider);
    final weekStart = ref.watch(weekStartProvider);
    ref.watch(refreshTickProvider);
    final range = dashRangeFor(period, DateTime.now(), weekStart);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'categoryDetail'))),
      body: FutureBuilder(
        future: _load(ref, range),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError || !snap.hasData) {
            return ErrorView(
              message: '${snap.error ?? ''}',
              onRetry: () => bumpRefresh(ref),
              lang: lang,
            );
          }
          return _body(context, ref, lang, snap.data!);
        },
      ),
    );
  }

  Future<_DetailData> _load(
    WidgetRef ref,
    ({DateTime start, DateTime end}) range,
  ) async {
    final cats = await ref.read(categoriesRepoProvider).all();
    final byId = {for (final c in cats) c.id: c};
    final parent = byId[categoryId];
    final kids = cats.where((c) => c.parentId == categoryId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final analytics = ref.read(analyticsRepoProvider);
    final raw = await analytics.expenseByCategory(range.start, range.end);
    final wallets = await ref.read(walletsRepoProvider).all();
    final txns = await ref
        .read(transactionsRepoProvider)
        .list(
          TxnFilter(
            type: 'expense',
            categoryIds: [categoryId, for (final k in kids) k.id],
            from: range.start,
            to: range.end,
            limit: 20,
          ),
        );
    return _DetailData(
      parent: parent,
      kids: kids,
      byCat: raw,
      wallets: wallets,
      txns: txns,
      byId: byId,
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    String lang,
    _DetailData d,
  ) {
    final parentName = d.parent == null
        ? Strings.get(lang, 'uncategorized')
        : Strings.categoryName(lang, d.parent!.nameKey, d.parent!.customName);
    final rolled = CategoryHierarchy.rollUp(d.byCat, d.byId.values.toList());
    final total = rolled[categoryId] ?? 0;
    final direct = d.byCat[categoryId] ?? 0;
    final rows = [
      for (final k in d.kids)
        if ((d.byCat[k.id] ?? 0) > 0) (cat: k, amount: d.byCat[k.id]!),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    final maxV = (rows.isEmpty ? direct : rows.first.amount).toDouble();
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Row(
          children: [
            CategoryAvatar(
              iconKey: d.parent?.icon,
              radius: 22,
              semanticLabel: parentName,
            ),
            const SizedBox(width: AppSpacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parentName,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  MoneyText(
                    millimes: total,
                    lang: lang,
                    type: 'expense',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (rows.isEmpty && direct == 0)
          EmptyState(
            title: Strings.get(lang, 'noTransactions'),
            body: Strings.get(lang, 'noTransactionsBody'),
            icon: Icons.receipt_long,
          )
        else ...[
          if (direct > 0)
            _amountRow(
              context,
              lang,
              iconKey: d.parent?.icon,
              name: parentName,
              amount: direct,
              maxV: maxV <= 0 ? 1 : maxV,
              onTap: null,
            ),
          for (final r in rows) ...[
            const Divider(height: 1, indent: 68),
            _amountRow(
              context,
              lang,
              iconKey: r.cat.icon,
              name: Strings.categoryName(lang, r.cat.nameKey, r.cat.customName),
              amount: r.amount,
              maxV: maxV <= 0 ? 1 : maxV,
              onTap: null,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SectionHeader(title: Strings.get(lang, 'recent')),
          if (d.txns.isEmpty)
            EmptyState(
              title: Strings.get(lang, 'noTransactions'),
              body: Strings.get(lang, 'noTransactionsBody'),
              icon: Icons.receipt_long,
            )
          else
            Column(
              children: [
                for (var i = 0; i < d.txns.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68),
                  Builder(
                    builder: (context) {
                      final t = d.txns[i];
                      final c = t.categoryId == null
                          ? null
                          : d.byId[t.categoryId];
                      final leaf = c == null
                          ? '—'
                          : Strings.categoryName(lang, c.nameKey, c.customName);
                      final wn =
                          d.wallets
                              .where((w) => w.id == t.walletId)
                              .map((w) => w.name)
                              .firstOrNull ??
                          '—';
                      return TransactionTile(
                        iconKey: c?.icon,
                        title: t.note.isEmpty ? leaf : t.note,
                        subtitle:
                            '${relativeDay(t.occurredAt, now, lang)} · $wn',
                        millimes: t.amountMillimes,
                        lang: lang,
                        type: t.type,
                        onTap: () =>
                            context.push('/add?edit=${t.id}&type=${t.type}'),
                      );
                    },
                  ),
                ],
              ],
            ),
        ],
      ],
    );
  }

  Widget _amountRow(
    BuildContext context,
    String lang, {
    required String? iconKey,
    required String name,
    required int amount,
    required double maxV,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            CategoryAvatar(iconKey: iconKey, radius: 18, semanticLabel: name),
            const SizedBox(width: AppSpacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MoneyText(
                        millimes: amount,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  LinearProgressIndicator(
                    value: maxV <= 0 ? 0 : amount / maxV,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailData {
  final Category? parent;
  final List<Category> kids;
  final Map<String?, int> byCat;
  final List<Wallet> wallets;
  final List<Transaction> txns;
  final Map<String, Category> byId;
  _DetailData({
    required this.parent,
    required this.kids,
    required this.byCat,
    required this.wallets,
    required this.txns,
    required this.byId,
  });
}
