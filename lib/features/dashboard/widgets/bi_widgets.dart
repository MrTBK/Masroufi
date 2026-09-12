part of '../dashboard_page.dart';

/// Global BI filter bar: period presets plus wallet, category, and type
/// scoping. Every change rewrites [biFilterProvider], which reloads the
/// single snapshot below, so the whole page recalculates from one point.
/// Option lists load independently (cheap all() reads); selections live
/// in the provider.
class _BiFilterBar extends ConsumerWidget {
  final String lang;
  const _BiFilterBar({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(biFilterProvider);
    final weekStart = ref.watch(weekStartProvider);
    final now = DateTime.now();
    final presets = <String, ({DateTime from, DateTime to})>{
      'today': (
        from: Periods.dayStart(now),
        to: Periods.dayStart(now).add(const Duration(days: 1)),
      ),
      'thisWeek': (() {
        final r = Periods.week(now, weekStart);
        return (from: r.start, to: r.end);
      })(),
      'thisMonth': (() {
        final r = Periods.month(now);
        return (from: r.start, to: r.end);
      })(),
      'thisYear': (() {
        final r = Periods.year(now);
        return (from: r.start, to: r.end);
      })(),
    };
    void apply(({DateTime from, DateTime to}) r) {
      ref.read(biFilterProvider.notifier).state = BiFilter(
        from: r.from,
        to: r.to,
        walletIds: filter.walletIds,
        categoryIds: filter.categoryIds,
        type: filter.type,
      );
    }

    // Option lists load once, independently of the snapshot; the bar
    // stays mounted across snapshot reloads.
    return FutureBuilder(
      future: Future.wait([
        ref.watch(walletsRepoProvider).all(includeArchived: false),
        ref.watch(categoriesRepoProvider).all(includeArchived: false),
      ]),
      builder: (context, snap) {
        final wallets = snap.data?[0] as List<Wallet>? ?? const <Wallet>[];
        final cats = snap.data?[1] as List<Category>? ?? const <Category>[];
        final roots = [
          for (final c in cats)
            if (c.parentId == null) c,
        ];
        String catName(String? id) {
          if (id == null) return Strings.get(lang, 'all');
          for (final c in cats) {
            if (c.id == id) {
              return Strings.categoryName(lang, c.nameKey, c.customName);
            }
          }
          return '—';
        }

        String walletName(String? id) {
          if (id == null) return Strings.get(lang, 'all');
          for (final w in wallets) {
            if (w.id == id) return w.name;
          }
          return '—';
        }

        final singleWallet = filter.walletIds.length == 1
            ? filter.walletIds.first
            : null;
        // Category selection stores one id (root or leaf); parents
        // expand to parent-plus-children on load.
        final singleCat = filter.categoryIds?.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in presets.entries) ...[
                    ChoiceChip(
                      label: Text(Strings.get(lang, e.key)),
                      selected:
                          filter.from == e.value.from &&
                          filter.to == e.value.to,
                      onSelected: (_) => apply(e.value),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: singleWallet,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'wallet'),
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
                        ref.read(biFilterProvider.notifier).state = BiFilter(
                          from: filter.from,
                          to: filter.to,
                          walletIds: v == null ? const [] : [v],
                          categoryIds: filter.categoryIds,
                          type: filter.type,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue:
                        singleCat != null && roots.any((c) => c.id == singleCat)
                        ? singleCat
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'category'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(Strings.get(lang, 'all')),
                      ),
                      for (final c in roots)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            Strings.categoryName(lang, c.nameKey, c.customName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        ref.read(biFilterProvider.notifier).state = BiFilter(
                          from: filter.from,
                          to: filter.to,
                          walletIds: filter.walletIds,
                          categoryIds: BiFilter.expandCategory(cats, v),
                          type: filter.type,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Screen-reader mirror of the active scope (icons alone
            // never carry it). Own line so chips never squeeze text.
            Text(
              '${walletName(singleWallet)} • ${catName(singleCat)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in const <String?>[
                    null,
                    'expense',
                    'income',
                  ]) ...[
                    ChoiceChip(
                      label: Text(
                        t == null
                            ? Strings.get(lang, 'all')
                            : Strings.get(lang, t),
                      ),
                      selected: filter.type == t,
                      onSelected: (_) =>
                          ref.read(biFilterProvider.notifier).state = BiFilter(
                            from: filter.from,
                            to: filter.to,
                            walletIds: filter.walletIds,
                            categoryIds: filter.categoryIds,
                            type: t,
                          ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Six KPI cells from one snapshot. Null KPIs render an em dash (no
/// data), never a zero masquerading as measurement.
class _KpiGrid extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _KpiGrid({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final effEnd = s.to.isBefore(now) ? s.to : now;
    var elapsed = effEnd.difference(Periods.dayStart(s.from)).inDays;
    if (elapsed < 1) elapsed = 1;
    final avgDaily = s.expense ~/ elapsed;
    final completed = [
      for (final m in s.trend)
        if (m.year < now.year || (m.year == now.year && m.month < now.month))
          m.expense,
    ];
    final avgMonthly = completed.isEmpty
        ? null
        : AnalyticsStats.averageMonthly(completed);
    final net = Kpi.netCashFlow(
      incomeMillimes: s.income,
      expenseMillimes: s.expense,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'insights')),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'income'),
                MoneyText(
                  millimes: s.income,
                  lang: lang,
                  type: 'income',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'expense'),
                MoneyText(
                  millimes: s.expense,
                  lang: lang,
                  type: 'expense',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'netCashFlow'),
                MoneyText(
                  millimes: net,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: net < 0 ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'savingsRate'),
                Text(
                  s.savingsRate == null ? '—' : '${s.savingsRate}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: (s.savingsRate ?? 0) < 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'avgDaily'),
                MoneyText(
                  millimes: avgDaily,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _kpiCell(
                context,
                Strings.get(lang, 'monthlyAverage'),
                avgMonthly == null
                    ? Text('—', style: Theme.of(context).textTheme.titleLarge)
                    : MoneyText(
                        millimes: avgMonthly,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiCell(BuildContext context, String label, Widget value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          value,
        ],
      ),
    );
  }
}

/// Forecast card: run-rate projection for the current month under the
/// wallet filter, against the overall budget. Hidden when there is
/// nothing to project from.
class _ForecastCard extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _ForecastCard({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final f = ForecastV2.project(
      spentSoFarMillimes: s.monthSpent,
      now: DateTime.now(),
      budgetMillimes: s.monthBudget,
    );
    if (f == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final over = (f.overrun ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'forecast')),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoneyText(
                millimes: f.projected,
                lang: lang,
                type: 'neutral',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (s.monthBudget != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${Money.inline(s.monthBudget!, lang: lang)} • '
                  '${Strings.get(lang, 'pace')} ${f.pacePct}%',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: (f.pacePct / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: over ? scheme.error : null,
                ),
                if (f.overrun != null && f.overrun! > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${Strings.get(lang, 'overrun')}: '
                    '${Money.inline(f.overrun!, lang: lang)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Filtered 6-month expense/income trend (twin bars per month).
class _BiTrend extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _BiTrend({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxV = 0;
    for (final m in s.trend) {
      if (m.expense > maxV) maxV = m.expense;
      if (m.income > maxV) maxV = m.income;
    }
    if (maxV <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'trend')),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in s.trend)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 10,
                              height: 12 + 64 * m.expense / maxV,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 10,
                              height: 12 + 64 * m.income / maxV,
                              decoration: BoxDecoration(
                                color: AppColors.income,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${m.month}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Drill-down category tree: rolled-up parents expand to children;
/// tapping any node opens its transaction detail. Type-aware (income
/// filter drills the income tree).
class _DrillTree extends ConsumerStatefulWidget {
  final String lang;
  final BiSnapshot s;
  const _DrillTree({required this.lang, required this.s});

  @override
  ConsumerState<_DrillTree> createState() => _DrillTreeState();
}

class _DrillTreeState extends ConsumerState<_DrillTree> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final s = widget.s;
    final type = context
        .dependOnInheritedWidgetOfExactType<_BiTypeScope>()
        ?.type;
    final raw = type == 'income' ? s.incomeByCat : s.byCategory;
    final byId = {for (final c in s.cats) c.id: c};
    final rolled = CategoryHierarchy.rollUp(raw, s.cats);
    final parents =
        rolled.entries
            .where((e) => e.value > 0)
            .where((e) => e.key == null || byId[e.key]?.parentId == null)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (parents.isEmpty) return const SizedBox.shrink();
    final total = type == 'income' ? s.income : s.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'byCategory')),
        Text(
          Strings.get(lang, 'drillDown'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        for (final e in parents) ...[
          _drillRow(
            context,
            lang,
            s,
            byId,
            total,
            e.key,
            e.value,
            isParent: true,
          ),
          if (_expanded == e.key)
            for (final c in s.cats)
              if (c.parentId == e.key && (rolled[c.id] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 20),
                  child: _drillRow(
                    context,
                    lang,
                    s,
                    byId,
                    total,
                    c.id,
                    rolled[c.id]!,
                    isParent: false,
                  ),
                ),
        ],
      ],
    );
  }

  Widget _drillRow(
    BuildContext context,
    String lang,
    BiSnapshot s,
    Map<String, Category> byId,
    int total,
    String? id,
    int value, {
    required bool isParent,
  }) {
    final name = _catName(lang, s.cats, id);
    final share = AnalyticsStats.sharePct(part: value, total: total);
    final hasKids =
        isParent && id != null && s.cats.any((c) => c.parentId == id);
    return InkWell(
      onTap: () {
        if (hasKids) {
          setState(() => _expanded = _expanded == id ? null : id);
        } else if (id != null) {
          context.push('/dashboard/category/$id');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            CategoryAvatar(
              iconKey: _catIcon(s.cats, id),
              radius: 16,
              semanticLabel: name,
            ),
            const SizedBox(width: AppSpacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (share != null)
                    Text(
                      '$share${Strings.get(lang, 'pctOfExpenses')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            MoneyText(
              millimes: value,
              lang: lang,
              type: 'neutral',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (hasKids)
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? (_expanded == id ? Icons.expand_more : Icons.chevron_left)
                    : (_expanded == id
                          ? Icons.expand_more
                          : Icons.chevron_right),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Biggest category movers vs the previous equal range, most extreme
/// first. Same check/warn icon language as health facts; hidden when
/// no category moved on a positive baseline.
class _Movers extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _Movers({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in s.cats) c.id: c};
    final names = {
      for (final id in {...s.byCategory.keys, ...s.prevByCat.keys})
        id: id == null
            ? Strings.get(lang, 'uncategorized')
            : byId[id] == null
            ? '—'
            : CategoryHierarchy.displayName(lang, byId[id]!, byId),
    };
    final movers = Insights.buildMovers(
      current: s.byCategory,
      previous: s.prevByCat,
      names: names,
      lang: lang,
    );
    if (movers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in movers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    m.warn ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: m.warn
                        ? Theme.of(context).colorScheme.error
                        : AppColors.income,
                    semanticLabel: m.text,
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(child: Text(m.text)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Wallet + priority breakdown from one snapshot. Wallets keep their
/// own icons (never category glyphs); priority inherits the category
/// classification. Shares are whole-percent, int-only.
class _WalletSection extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _WalletSection({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (final w in s.wallets)
        if ((s.byWallet[w.id] ?? 0) > 0) w,
    ];
    final prioTotal = s.byPriority.values.fold(0, (a, b) => a + b);
    if (rows.isEmpty && prioTotal <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'byWallet')),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 68),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                WalletAvatar(
                  iconKey: rows[i].icon,
                  radius: 16,
                  semanticLabel: rows[i].name,
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Text(
                    rows[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                MoneyText(
                  millimes: s.byWallet[rows[i].id] ?? 0,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        if (prioTotal > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final p in const ['important', 'normal', 'fun'])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, p),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      MoneyText(
                        millimes: s.byPriority[p] ?? 0,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Inherited type scope so the drill tree follows the type chips
/// without threading parameters through every row.
class _BiTypeScope extends InheritedWidget {
  final String? type;
  const _BiTypeScope({required this.type, required super.child});
  @override
  bool updateShouldNotify(_BiTypeScope old) => old.type != type;
}
