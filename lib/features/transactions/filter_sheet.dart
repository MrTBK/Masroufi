import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/periods.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import 'history_page.dart' show catFilterProvider, walletFilterProvider;
import 'transactions_page.dart'
    show txnDatePresetProvider, txnDateRangeProvider, txnSearchProvider, txnTypeFilterProvider;

/// Number of active transaction filters (badge on the filter button).
int activeFilterCount({
  required String? type,
  required String? walletId,
  required String? catId,
  required String search,
  bool hasDateRange = false,
}) =>
    (type != null ? 1 : 0) +
    (walletId != null ? 1 : 0) +
    (catId != null ? 1 : 0) +
    (search.isNotEmpty ? 1 : 0) +
    (hasDateRange ? 1 : 0);

/// Date presets for the timeline window (ids double as chip labels via
/// existing period keys; 'custom' uses the dedicated range key).
const _datePresets = ['today', 'thisWeek', 'thisMonth'];

({DateTime start, DateTime end}) _presetRange(
  String preset,
  DateTime now,
  String weekStart,
) => switch (preset) {
  'today' => Periods.day(now),
  'thisWeek' => Periods.week(now, weekStart),
  _ => Periods.month(now),
};

/// Bottom-sheet filter panel for the Today-first Transactions page.
/// Applies live (no Apply step to forget); Clear resets everything.
/// Replaces the old wall of inline chips + dropdown boxes + search field.
Future<void> showFilterSheet(BuildContext context, WidgetRef ref) {
  final lang = ref.read(languageProvider);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(c).viewInsets.bottom + AppSpacing.lg,
        ),
        child: _FilterSheetBody(lang: lang),
      ),
    ),
  );
}

/// Date window chips: all-time + presets + custom range dialog.
/// Live-applied like every other filter; the range (not the chip id)
/// is the source of truth for the timeline query.
class _DateChips extends ConsumerWidget {
  final String lang;
  const _DateChips({required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(txnDatePresetProvider);
    final weekStart = ref.watch(weekStartProvider);
    final now = DateTime.now();
    String label(String p) => Strings.get(
      lang,
      p == 'today'
          ? 'today'
          : p == 'thisWeek'
          ? 'thisWeek'
          : 'thisMonth',
    );
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        FilterChip(
          label: Text(Strings.get(lang, 'dateAll')),
          selected: preset == null,
          onSelected: (_) {
            ref.read(txnDateRangeProvider.notifier).state = null;
            ref.read(txnDatePresetProvider.notifier).state = null;
          },
        ),
        for (final p in _datePresets)
          FilterChip(
            label: Text(label(p)),
            selected: preset == p,
            onSelected: (_) {
              final r = _presetRange(p, now, weekStart);
              ref.read(txnDateRangeProvider.notifier).state = (
                from: r.start,
                to: r.end,
              );
              ref.read(txnDatePresetProvider.notifier).state = p;
            },
          ),
        FilterChip(
          label: Text(Strings.get(lang, 'customRange')),
          selected: preset == 'custom',
          onSelected: (_) async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020, 1, 1),
              lastDate: DateTime(now.year + 1, 12, 31),
              initialDateRange: ref.read(txnDateRangeProvider) == null
                  ? null
                  : DateTimeRange(
                      start: ref.read(txnDateRangeProvider)!.from,
                      end: ref
                          .read(txnDateRangeProvider)!
                          .to
                          .subtract(const Duration(days: 1)),
                    ),
            );
            if (picked == null) return;
            ref.read(txnDateRangeProvider.notifier).state = (
              from: DateTime(
                picked.start.year,
                picked.start.month,
                picked.start.day,
              ),
              // Half-open: include the whole picked end day.
              to: DateTime(
                picked.end.year,
                picked.end.month,
                picked.end.day,
              ).add(const Duration(days: 1)),
            );
            ref.read(txnDatePresetProvider.notifier).state = 'custom';
          },
        ),
      ],
    );
  }
}

class _FilterSheetBody extends ConsumerStatefulWidget {
  final String lang;
  const _FilterSheetBody({required this.lang});

  @override
  ConsumerState<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends ConsumerState<_FilterSheetBody> {
  late final TextEditingController _searchCtl;

  @override
  void initState() {
    super.initState();
    // Created once: rebuilds from other filters must not steal focus.
    _searchCtl = TextEditingController(text: ref.read(txnSearchProvider));
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final type = ref.watch(txnTypeFilterProvider);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  Strings.get(lang, 'filters'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(txnTypeFilterProvider.notifier).state = null;
                  ref.read(walletFilterProvider.notifier).state = null;
                  ref.read(catFilterProvider.notifier).state = null;
                  ref.read(txnSearchProvider.notifier).state = '';
                  ref.read(txnDateRangeProvider.notifier).state = null;
                  ref.read(txnDatePresetProvider.notifier).state = null;
                  _searchCtl.clear();
                },
                child: Text(Strings.get(lang, 'clearFilters')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              hintText: Strings.get(lang, 'search'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (v) => ref.read(txnSearchProvider.notifier).state = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              FilterChip(
                label: Text(Strings.get(lang, 'all')),
                selected: type == null,
                onSelected: (_) =>
                    ref.read(txnTypeFilterProvider.notifier).state = null,
              ),
              for (final t in ['expense', 'income', 'transfer'])
                FilterChip(
                  label: Text(Strings.get(lang, t)),
                  selected: type == t,
                  onSelected: (_) =>
                      ref.read(txnTypeFilterProvider.notifier).state = t,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder(
            future: Future.wait([
              ref.watch(walletsRepoProvider).all(includeArchived: true),
              ref.watch(categoriesRepoProvider).all(includeArchived: true),
            ]),
            builder: (context, meta) {
              if (!meta.hasData) return const SizedBox.shrink();
              final wallets = meta.data![0] as List<Wallet>;
              final cats = meta.data![1] as List<Category>;
              final catById = {for (final c in cats) c.id: c};
              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: ref.watch(walletFilterProvider),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'filterWallet'),
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
                        ref.read(walletFilterProvider.notifier).state = v,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: ref.watch(catFilterProvider),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'filterCategory'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(Strings.get(lang, 'all')),
                      ),
                      for (final c in cats)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            CategoryHierarchy.displayName(lang, c, catById),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        ref.read(catFilterProvider.notifier).state = v,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            Strings.get(lang, 'dateFilter'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _DateChips(lang: lang),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Strings.get(lang, 'done')),
          ),
        ],
      ),
    );
  }
}
