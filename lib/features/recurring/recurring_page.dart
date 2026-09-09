import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/design.dart';
import '../../core/money/recurring.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';

/// Recurring rules: salary, rent, subscriptions. Generation is user
/// controlled (active/paused per rule, optional end date); due occurrences
/// materialize at startup via [generateDue].
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(recurringRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'recurring'))),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: Strings.get(lang, 'newRule'),
        onPressed: () => _ruleDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<RecurringRule>>(
        stream: repo.watch(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final rules = snap.data!;
          if (rules.isEmpty) {
            return EmptyState(
              title: Strings.get(lang, 'noRecurring'),
              body: Strings.get(lang, 'noRecurringBody'),
              icon: Icons.repeat,
            );
          }
          return FutureBuilder(
            future: Future.wait([
              ref.read(walletsRepoProvider).all(),
              ref.read(categoriesRepoProvider).all(),
            ]),
            builder: (context, meta) {
              final wallets = meta.hasData
                  ? meta.data![0] as List<Wallet>
                  : <Wallet>[];
              final cats = meta.hasData
                  ? meta.data![1] as List<Category>
                  : <Category>[];
              String wn(String id) =>
                  wallets
                      .where((w) => w.id == id)
                      .map((w) => w.name)
                      .firstOrNull ??
                  '—';
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
                itemCount: rules.length,
                itemBuilder: (context, i) {
                  final r = rules[i];
                  return ListTile(
                    leading: Icon(
                      r.type == 'expense'
                          ? Icons.remove_circle
                          : Icons.add_circle,
                    ),
                    title: Text(
                      r.note.isEmpty
                          ? '${cn(r.categoryId)} • ${wn(r.walletId)}'
                          : r.note,
                    ),
                    subtitle: Text(
                      '${Strings.get(lang, 'freq_${r.frequency}')} • '
                      '${Strings.get(lang, 'nextUp')}: '
                      '${r.nextOccurrence.year}-${r.nextOccurrence.month.toString().padLeft(2, '0')}-'
                      '${r.nextOccurrence.day.toString().padLeft(2, '0')} • '
                      '${r.isActive ? Strings.get(lang, 'active') : Strings.get(lang, 'paused')}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoneyText(
                          millimes: r.amountMillimes,
                          lang: lang,
                          type: r.type,
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'skip') {
                              await repo.skipOccurrence(r.id);
                            } else if (v == 'toggle') {
                              await repo.updateRule(
                                r.id,
                                isActive: !r.isActive,
                              );
                            } else if (v == 'delete') {
                              final ok = await _confirm(context, lang);
                              if (ok == true) await repo.remove(r.id);
                            }
                            bumpRefresh(ref);
                          },
                          itemBuilder: (c) => [
                            PopupMenuItem(
                              value: 'skip',
                              child: Text(Strings.get(lang, 'skip')),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(
                                Strings.get(
                                  lang,
                                  r.isActive ? 'pause' : 'resume',
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(Strings.get(lang, 'delete')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String lang) => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(Strings.get(lang, 'deleteRule')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(Strings.get(lang, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(Strings.get(lang, 'delete')),
        ),
      ],
    ),
  );

  Future<void> _ruleDialog(
    BuildContext context,
    WidgetRef ref,
    RecurringRule? r,
  ) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(recurringRepoProvider);
    final wallets = await ref
        .read(walletsRepoProvider)
        .all(includeArchived: false);
    final cats = await ref
        .read(categoriesRepoProvider)
        .all(includeArchived: false);
    if (!context.mounted) return;
    var type = r?.type ?? 'expense';
    var frequency = r?.frequency ?? 'monthly';
    final amountCtl = TextEditingController(
      text: r == null ? '' : (r.amountMillimes / 1000).toStringAsFixed(3),
    );
    final noteCtl = TextEditingController(text: r?.note ?? '');
    var walletId =
        r?.walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);
    var categoryId = r?.categoryId;
    var start = r?.startDate ?? DateTime.now();
    var end = r?.endDate;
    var error = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(Strings.get(lang, 'newRule')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'expense',
                      label: Text(Strings.get(lang, 'expense')),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text(Strings.get(lang, 'income')),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setS(() {
                    type = s.first;
                    // Income must never offer expense categories (and vice
                    // versa): drop a selection that belongs to the other kind.
                    if (categoryId != null &&
                        !cats.any(
                          (x) => x.id == categoryId && x.kind == type,
                        )) {
                      categoryId = null;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'amount'),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'frequency'),
                  ),
                  items: [
                    for (final f in Recurring.frequencies)
                      DropdownMenuItem(
                        value: f,
                        child: Text(Strings.get(lang, 'freq_$f')),
                      ),
                  ],
                  onChanged: (v) => setS(() => frequency = v ?? frequency),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: walletId,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'wallet'),
                  ),
                  items: [
                    for (final w in wallets)
                      DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => setS(() => walletId = v),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (c) {
                    final catsForType = cats
                        .where((x) => x.kind == type)
                        .toList();
                    final effectiveCat =
                        catsForType.any((x) => x.id == categoryId)
                        ? categoryId
                        : null;
                    return DropdownButtonFormField<String>(
                      key: ValueKey('recurr-cat-$type'),
                      initialValue: effectiveCat,
                      decoration: InputDecoration(
                        labelText: type == 'income'
                            ? Strings.get(lang, 'incomeCategory')
                            : Strings.get(lang, 'category'),
                      ),
                      items: [
                        for (final x in catsForType)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text(
                              Strings.categoryName(
                                lang,
                                x.nameKey,
                                x.customName,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setS(() => categoryId = v),
                    );
                  },
                ),
                TextField(
                  controller: noteCtl,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'note'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Strings.get(lang, 'startDate')),
                  subtitle: Text(
                    '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final p = await showDatePicker(
                      context: c,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: start,
                    );
                    if (p != null) setS(() => start = p);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Strings.get(lang, 'endDate')),
                  subtitle: Text(
                    end == null
                        ? '—'
                        : '${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: end == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setS(() => end = null),
                        ),
                  onTap: () async {
                    final p = await showDatePicker(
                      context: c,
                      firstDate: start,
                      lastDate: DateTime(2100),
                      initialDate: end ?? start,
                    );
                    if (p != null) setS(() => end = p);
                  },
                ),
                if (error)
                  Text(
                    Strings.get(lang, 'invalidAmount'),
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(Strings.get(lang, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                int amount;
                try {
                  amount = Money.parse(amountCtl.text);
                } catch (_) {
                  setS(() => error = true);
                  return;
                }
                if (walletId == null) {
                  setS(() => error = true);
                  return;
                }
                if (r == null) {
                  await repo.create(
                    type: type,
                    amountMillimes: amount,
                    walletId: walletId!,
                    categoryId: categoryId,
                    note: noteCtl.text,
                    frequency: frequency,
                    startDate: start,
                    endDate: end,
                  );
                } else {
                  await repo.updateRule(
                    r.id,
                    amountMillimes: amount,
                    walletId: walletId,
                    categoryId: categoryId,
                    note: noteCtl.text,
                    frequency: frequency,
                    endDate: end,
                  );
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
