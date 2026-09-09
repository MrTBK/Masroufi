import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hide intl's own TextDirection class: it shadows Flutter's enum and
// breaks TextDirection.ltr/rtl wherever both libraries are imported.
import 'package:intl/intl.dart' hide TextDirection;

import '../../app/providers.dart';
import '../../core/analytics/summary.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/masroufi_nav.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';

/// MIZANIA — dedicated budget experience (spec §18).
/// Overall monthly behavior unchanged (same repos + FinanceCalc);
/// presentation upgraded: month header → totals → progress → categories.
class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});
  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(budgetsRepoProvider);
    final catRepo = ref.watch(categoryBudgetsRepoProvider);
    final catsRepo = ref.watch(categoriesRepoProvider);
    final now = DateTime.now();
    // Localized month (سبتمبر / septembre / September): never hardcode
    // English month names into the Arabic/French UI.
    String monthName() {
      try {
        final locale = switch (lang) {
          'ar' => 'ar',
          'fr' => 'fr',
          _ => 'en',
        };
        return DateFormat('MMMM yyyy', locale).format(now);
      } catch (_) {
        return '${now.month}/${now.year}';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: HomeTitle(
          text: '${Strings.get(lang, 'mizania')} • ${monthName()}',
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
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: Strings.get(lang, 'setBudget'),
        onPressed: () => _dialog(context, ref),
        child: const Icon(Icons.edit),
      ),
      body: FutureBuilder(
        future: Future.wait([
          repo.getMonth(now.year, now.month),
          repo.status(now.year, now.month),
          catRepo.forMonth(now.year, now.month),
          catsRepo.all(),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final budget = snap.data![0] as Budget?;
          final status =
              snap.data![1] as ({int spent, int remaining, double pct});
          final catBudgets = snap.data![2] as List<CategoryBudget>;
          final cats = snap.data![3] as List<Category>;
          final byId = {for (final c in cats) c.id: c};
          // Category budgets track spending: only expense kinds are offered.
          // Parents and leaves are both accepted (rolled-up display).
          final expenseCats = cats.where((c) => c.kind != 'income').toList();
          String catName(String id) {
            final c = byId[id];
            if (c == null) return '—';
            return CategoryHierarchy.displayName(lang, c, byId);
          }

          String catIcon(String id) =>
              cats.where((c) => c.id == id).map((c) => c.icon).firstOrNull ??
              'other';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (budget == null)
                EmptyState(
                  title: Strings.get(lang, 'budget'),
                  body: Strings.get(lang, 'setBudget'),
                  icon: Icons.savings,
                )
              else
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, 'totalBudget'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      MoneyText(
                        millimes: budget.amountMillimes,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _row(
                        context,
                        Strings.get(lang, 'spent'),
                        status.spent,
                        lang,
                      ),
                      _row(
                        context,
                        Strings.get(lang, 'remaining'),
                        status.remaining,
                        lang,
                      ),
                      Text(
                        Brand.nameFor(lang),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      BudgetBar(
                        spentMillimes: status.spent,
                        totalMillimes: budget.amountMillimes,
                        lang: lang,
                      ),
                      const SizedBox(height: 8),
                      _guidance(
                        context,
                        lang,
                        budget.amountMillimes,
                        status.spent,
                        now,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          await repo.remove(now.year, now.month);
                          bumpRefresh(ref);
                          setState(() {});
                        },
                        child: Text(Strings.get(lang, 'delete')),
                      ),
                    ],
                  ),
                ),
              SectionHeader(
                title: Strings.get(lang, 'categoryBudgets'),
                actionLabel: '+ ${Strings.get(lang, 'newCatBudget')}',
                onAction: () => _catDialog(context, ref, expenseCats, null),
              ),
              if (catBudgets.isEmpty)
                Text(
                  Strings.get(lang, 'newCatBudget'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (final cb in catBudgets)
                FutureBuilder(
                  future: catRepo.status(cb.categoryId, now.year, now.month),
                  builder: (context, st) {
                    final s =
                        st.data ??
                        (spent: 0, remaining: cb.amountMillimes, pct: 0.0);
                    final over = s.spent > cb.amountMillimes;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () =>
                              _catDialog(context, ref, expenseCats, cb),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                CategoryAvatar(
                                  iconKey: catIcon(cb.categoryId),
                                  semanticLabel: catName(cb.categoryId),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              catName(cb.categoryId),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ),
                                          if (over)
                                            Text(
                                              Strings.get(lang, 'overBudget'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      // "spent / total" is a pure numeric run:
                                      // force LTR so the slash never migrates
                                      // in RTL paragraphs.
                                      Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Text(
                                          budgetFraction(
                                            s.spent,
                                            cb.amountMillimes,
                                            lang,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      BudgetBar(
                                        spentMillimes: s.spent,
                                        totalMillimes: cb.amountMillimes,
                                        lang: lang,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 68),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  /// Daily spending guidance: remaining budget ÷ days left (incl.
  /// today). Same deterministic helper as the Transactions indicator;
  /// over budget renders the warning state instead of a target.
  Widget _guidance(
    BuildContext context,
    String lang,
    int budget,
    int spent,
    DateTime now,
  ) {
    final g = dailyGuidance(
      budgetMillimes: budget,
      spentMillimes: spent,
      now: now,
    );
    final scheme = Theme.of(context).colorScheme;
    if (g.remaining < 0) {
      return Row(
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
        ],
      );
    }
    return Text(
      '${Strings.get(lang, 'suggestedDaily')} '
      '${Money.inline(g.suggested, lang: lang)} · '
      '${g.daysLeft} ${Strings.get(lang, 'daysLeft')}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _row(BuildContext context, String label, int value, String lang) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            MoneyText(
              millimes: value,
              lang: lang,
              // Remaining can go negative (over budget): neutral keeps the
              // formatter-owned sign attached in every locale.
              type: 'neutral',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Future<void> _dialog(BuildContext context, WidgetRef ref) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(budgetsRepoProvider);
    final now = DateTime.now();
    final existing = await repo.getMonth(now.year, now.month);
    final ctl = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountMillimes / 1000).toStringAsFixed(3),
    );
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(Strings.get(lang, 'setBudget')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: Strings.get(lang, 'amountHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(Strings.get(lang, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final v = Money.parse(ctl.text);
                await repo.upsert(now.year, now.month, v);
                bumpRefresh(ref);
                if (d.mounted) Navigator.pop(d);
                setState(() {});
              } catch (_) {}
            },
            child: Text(Strings.get(lang, 'save')),
          ),
        ],
      ),
    );
  }

  Future<void> _catDialog(
    BuildContext context,
    WidgetRef ref,
    List<Category> cats,
    CategoryBudget? existing,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(categoryBudgetsRepoProvider);
    final now = DateTime.now();
    var catId =
        existing?.categoryId ?? (cats.isNotEmpty ? cats.first.id : null);
    final ctl = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountMillimes / 1000).toStringAsFixed(3),
    );
    var error = false;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(Strings.get(lang, 'newCatBudget')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: catId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'category'),
                ),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        CategoryHierarchy.displayName(lang, c, {
                          for (final x in cats) x.id: x,
                        }),
                      ),
                    ),
                ],
                onChanged: (v) => setS(() => catId = v),
              ),
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: Strings.get(lang, 'amountHint'),
                ),
              ),
              if (error)
                Text(
                  Strings.get(lang, 'invalidAmount'),
                  style: TextStyle(color: Theme.of(d).colorScheme.error),
                ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await repo.remove(existing.categoryId, now.year, now.month);
                  bumpRefresh(ref);
                  if (d.mounted) Navigator.pop(d);
                  setState(() {});
                },
                child: Text(Strings.get(lang, 'delete')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(Strings.get(lang, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (catId == null) {
                  setS(() => error = true);
                  return;
                }
                try {
                  final v = Money.parse(ctl.text);
                  await repo.upsert(catId!, now.year, now.month, v);
                  bumpRefresh(ref);
                  if (d.mounted) Navigator.pop(d);
                  setState(() {});
                } catch (_) {
                  setS(() => error = true);
                }
              },
              child: Text(Strings.get(lang, 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
