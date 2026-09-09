import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/design.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';

/// Debts (§5.4): both directions, partial payments, history.
/// Payments move wallets through the normal ledger exactly once.
class DebtsPage extends ConsumerStatefulWidget {
  const DebtsPage({super.key});
  @override
  ConsumerState<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends ConsumerState<DebtsPage> {
  String direction = 'owed';

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    ref.watch(refreshTickProvider);
    final repo = ref.watch(debtsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'debts'))),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: Strings.get(lang, 'newDebt'),
        onPressed: () => _debtDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'owed',
                  label: Text(Strings.get(lang, 'owedToMe')),
                ),
                ButtonSegment(
                  value: 'owe',
                  label: Text(Strings.get(lang, 'iOwe')),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (s) => setState(() => direction = s.first),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Debt>>(
              stream: repo.watch(),
              builder: (context, snap) {
                if (!snap.hasData) return const LoadingView();
                final debts = snap.data!
                    .where((d) => d.direction == direction)
                    .toList();
                if (debts.isEmpty) {
                  return EmptyState(
                    title: Strings.get(lang, 'debts'),
                    body: Strings.get(lang, 'newDebt'),
                    icon: Icons.handshake,
                  );
                }
                return ListView.builder(
                  itemCount: debts.length,
                  itemBuilder: (context, i) {
                    final d = debts[i];
                    return FutureBuilder<int>(
                      future: repo.remaining(d.id),
                      builder: (context, rem) {
                        final remaining = rem.data ?? d.originalMillimes;
                        final settled = d.status == 'settled';
                        final scheme = Theme.of(context).colorScheme;
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: scheme.secondaryContainer,
                                foregroundColor: scheme.onSecondaryContainer,
                                child: Icon(
                                  d.direction == 'owe'
                                      ? Icons.north_east
                                      : Icons.south_west,
                                  semanticLabel: d.person,
                                ),
                              ),
                              title: Text(
                                d.person,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                settled
                                    ? Strings.get(lang, 'settle')
                                    : '${Strings.get(lang, d.direction == 'owe' ? 'iOwe' : 'owedToMe')} · '
                                          '${Money.inline(remaining, lang: lang)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  '${Money.format(d.originalMillimes - remaining, lang: lang)} / '
                                  '${Money.format(d.originalMillimes, lang: lang)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              onTap: () => _detailSheet(context, ref, d),
                            ),
                            const Divider(height: 1, indent: 72),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _detailSheet(BuildContext context, WidgetRef ref, Debt d) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(debtsRepoProvider);
    final history = await repo.history(d.id);
    final wallets = await ref
        .read(walletsRepoProvider)
        .all(includeArchived: false);
    String wn(String id) =>
        wallets.where((w) => w.id == id).map((w) => w.name).firstOrNull ?? '—';
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
              Text(d.person, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (d.status == 'open')
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    _payDialog(context, ref, d);
                  },
                  child: Text(Strings.get(lang, 'pay')),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _debtDialog(context, ref, d);
                },
                child: Text(Strings.get(lang, 'edit')),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final h in history)
                      ListTile(
                        title: Text(h.note.isEmpty ? wn(h.walletId) : h.note),
                        subtitle: Text(
                          '${h.occurredAt.year}-${h.occurredAt.month.toString().padLeft(2, '0')}-${h.occurredAt.day.toString().padLeft(2, '0')}',
                        ),
                        trailing: MoneyText(
                          millimes: h.amountMillimes,
                          lang: lang,
                          type: 'income',
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

  Future<void> _payDialog(BuildContext context, WidgetRef ref, Debt d) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(debtsRepoProvider);
    final wallets = await ref
        .read(walletsRepoProvider)
        .all(includeArchived: false);
    if (!context.mounted) return;
    final ctl = TextEditingController();
    var walletId = wallets.isNotEmpty ? wallets.first.id : null;
    var error = '';
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(Strings.get(lang, 'pay')),
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
              if (error.isNotEmpty)
                Text(
                  error,
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
                  setS(() => error = Strings.get(lang, 'invalidAmount'));
                  return;
                }
                if (walletId == null) {
                  setS(() => error = Strings.get(lang, 'required'));
                  return;
                }
                try {
                  await repo.pay(
                    debtId: d.id,
                    amountMillimes: v,
                    walletId: walletId!,
                  );
                } on ArgumentError {
                  setS(() => error = Strings.get(lang, 'overpaymentBlocked'));
                  return;
                } on StateError {
                  setS(() => error = Strings.get(lang, 'settle'));
                  return;
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

  Future<void> _debtDialog(BuildContext context, WidgetRef ref, Debt? d) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(debtsRepoProvider);
    final personCtl = TextEditingController(text: d?.person ?? '');
    final amountCtl = TextEditingController(
      text: d == null ? '' : (d.originalMillimes / 1000).toStringAsFixed(3),
    );
    var dir = d?.direction ?? direction;
    var error = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(Strings.get(lang, 'newDebt')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'owed',
                    label: Text(Strings.get(lang, 'owedToMe')),
                  ),
                  ButtonSegment(
                    value: 'owe',
                    label: Text(Strings.get(lang, 'iOwe')),
                  ),
                ],
                selected: {dir},
                onSelectionChanged: (s) => setS(() => dir = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: personCtl,
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'person'),
                ),
              ),
              TextField(
                controller: amountCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Strings.get(lang, 'original'),
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
                if (personCtl.text.trim().isEmpty) {
                  setS(() => error = true);
                  return;
                }
                int v;
                try {
                  v = Money.parse(amountCtl.text);
                } catch (_) {
                  setS(() => error = true);
                  return;
                }
                if (d == null) {
                  await repo.create(
                    person: personCtl.text,
                    direction: dir,
                    originalMillimes: v,
                  );
                } else {
                  await repo.updateDebt(d.id, person: personCtl.text);
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
