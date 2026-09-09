import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/repositories/savings_repo.dart';

/// Savings goals (§5.3). Separate ledger: contributions never touch wallets.
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(savingsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'savingsGoals'))),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: Strings.get(lang, 'newGoal'),
        onPressed: () => _goalDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<SavingsGoal>>(
        stream: repo.watch(includeArchived: true),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final goals = snap.data!;
          // Track 3 decision (documented as designed): savings stay a
          // separate ledger, default unlinked — contributing never moves
          // wallet money. Shown inline so the choice is explicit.
          final note = Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md2,
              AppSpacing.md,
              0,
            ),
            child: Text(
              Strings.get(lang, 'savingsSeparate'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
          if (goals.isEmpty) {
            return Column(
              children: [
                note,
                Expanded(
                  child: EmptyState(
                    title: Strings.get(lang, 'savingsGoals'),
                    body: Strings.get(lang, 'newGoal'),
                    icon: Icons.savings,
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              note,
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: goals.length,
                  itemBuilder: (context, i) {
                    final g = goals[i];
                    return FutureBuilder<int>(
                      future: repo.currentAmount(g.id),
                      builder: (context, amt) {
                        final current = amt.data ?? 0;
                        final pct = SavingsRepo.progress(
                          current,
                          g.targetMillimes,
                        );
                        final remaining = g.targetMillimes - current;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            onTap: () => _detailSheet(context, ref, g),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        g.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    if (g.isArchived)
                                      Text(
                                        Strings.get(lang, 'archived'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    '${Money.format(current, lang: lang)} / '
                                    '${Money.format(g.targetMillimes, lang: lang)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                BudgetBar(
                                  spentMillimes: current,
                                  totalMillimes: g.targetMillimes,
                                  lang: lang,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${Strings.get(lang, 'remainingGoal')}: '
                                  '${Money.inline(remaining, lang: lang)}'
                                  '${pct * 100 >= 100 ? '' : ' • ${(pct * 100).toStringAsFixed(1)}%'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _detailSheet(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal g,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(savingsRepoProvider);
    final history = await repo.history(g.id);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(g.name, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(c);
                        _moneyDialog(context, ref, g, true);
                      },
                      child: Text(Strings.get(lang, 'contribute')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(c);
                        _moneyDialog(context, ref, g, false);
                      },
                      child: Text(Strings.get(lang, 'withdraw')),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _goalDialog(context, ref, g);
                },
                child: Text(Strings.get(lang, 'edit')),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final h in history)
                      ListTile(
                        title: Text(
                          h.note.isEmpty
                              ? '${h.occurredAt.year}-${h.occurredAt.month.toString().padLeft(2, '0')}-${h.occurredAt.day.toString().padLeft(2, '0')}'
                              : h.note,
                        ),
                        trailing: MoneyText(
                          millimes: h.amountMillimes,
                          lang: lang,
                          type: h.amountMillimes >= 0 ? 'income' : 'expense',
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
    bumpRefresh(ref);
  }

  Future<void> _moneyDialog(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal g,
    bool isAdd,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(savingsRepoProvider);
    final ctl = TextEditingController();
    var error = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(Strings.get(lang, isAdd ? 'contribute' : 'withdraw')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(Strings.get(lang, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                int v;
                try {
                  v = Money.parse(ctl.text);
                } catch (_) {
                  setS(() => error = true);
                  return;
                }
                await repo.addContribution(g.id, isAdd ? v : -v);
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

  Future<void> _goalDialog(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal? g,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(savingsRepoProvider);
    final nameCtl = TextEditingController(text: g?.name ?? '');
    final targetCtl = TextEditingController(
      text: g == null ? '' : (g.targetMillimes / 1000).toStringAsFixed(3),
    );
    var error = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(Strings.get(lang, 'newGoal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'goalName'),
                ),
              ),
              TextField(
                controller: targetCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'targetAmount'),
                ),
              ),
              if (error)
                Text(
                  Strings.get(lang, 'invalidAmount'),
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
          actions: [
            if (g != null)
              TextButton(
                onPressed: () async {
                  await repo.setArchived(g.id, !g.isArchived);
                  bumpRefresh(ref);
                  if (c.mounted) Navigator.pop(c);
                },
                child: Text(
                  Strings.get(lang, g.isArchived ? 'unarchive' : 'archive'),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(Strings.get(lang, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) {
                  setS(() => error = true);
                  return;
                }
                int target;
                try {
                  target = Money.parse(targetCtl.text);
                } catch (_) {
                  setS(() => error = true);
                  return;
                }
                if (g == null) {
                  await repo.create(name: nameCtl.text, targetMillimes: target);
                } else {
                  await repo.rename(g.id, nameCtl.text);
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
}
