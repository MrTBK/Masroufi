import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/widgets.dart';

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
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${Strings.get(lang, 'budget')} • ${now.month}/${now.year}',
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _dialog(context, ref),
        child: const Icon(Icons.edit),
      ),
      body: FutureBuilder(
        future: Future.wait([
          repo.getMonth(now.year, now.month),
          repo.status(now.year, now.month),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final budget = snap.data![0] as dynamic;
          final status =
              snap.data![1] as ({int spent, int remaining, double pct});
          if (budget == null) {
            return EmptyState(
              title: Strings.get(lang, 'budget'),
              body: Strings.get(lang, 'setBudget'),
              icon: Icons.savings,
            );
          }
          final pct = status.pct.clamp(0.0, 1.0);
          final over = status.spent > (budget.amountMillimes as int);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(
                          context,
                          Strings.get(lang, 'budget'),
                          budget.amountMillimes as int,
                          lang,
                        ),
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
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: pct,
                          minHeight: 12,
                          color: over
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(status.pct * 100).toStringAsFixed(0)}% ${Strings.get(lang, 'used')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: over
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                        ),
                      ],
                    ),
                  ),
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
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, String label, int value, String lang) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              Money.format(value, lang: lang),
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
}
