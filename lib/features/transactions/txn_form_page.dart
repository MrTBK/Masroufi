import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/notify/notifier.dart';
import '../../core/widget/masroufi_widget.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import 'category_picker.dart';

/// Add or edit expense/income/transfer. Optimized for speed:
/// amount (autofocus, numeric) -> category -> wallet -> save.
/// Each type shows its own fields: expense offers expense categories with
/// "Pay from"; income offers income categories with "Money goes to";
/// transfer offers From/To wallets and no category.
class TxnFormPage extends ConsumerStatefulWidget {
  final String initialType;
  final String? editId;
  const TxnFormPage({super.key, required this.initialType, this.editId});

  @override
  ConsumerState<TxnFormPage> createState() => _TxnFormPageState();
}

class _TxnFormPageState extends ConsumerState<TxnFormPage> {
  late String type;
  final amountCtl = TextEditingController();
  final noteCtl = TextEditingController();
  String? walletId;
  String? toWalletId;
  String? categoryId;
  DateTime when = DateTime.now();
  bool loading = true;
  bool saving = false;
  String? error;
  List<Wallet> wallets = [];
  List<Category> cats = [];
  Map<String, int> balances = {};

  @override
  void initState() {
    super.initState();
    type = ['expense', 'income', 'transfer'].contains(widget.initialType)
        ? widget.initialType
        : 'expense';
    _load();
  }

  Future<void> _load() async {
    final walletsRepo = ref.read(walletsRepoProvider);
    final w = await walletsRepo.all(includeArchived: false);
    final c = await ref
        .read(categoriesRepoProvider)
        .all(includeArchived: false);
    final b = <String, int>{};
    for (final wallet in w) {
      b[wallet.id] = await walletsRepo.balance(wallet);
    }
    Transaction? existing;
    if (widget.editId != null) {
      existing =
          await (ref
                  .read(appDbProvider)
                  .select(ref.read(appDbProvider).transactions)
                ..where((t) => t.id.equals(widget.editId!)))
              .getSingleOrNull();
    }
    if (!mounted) return;
    final initialType = existing?.type ?? type;
    setState(() {
      wallets = w;
      cats = c;
      balances = b;
      type = initialType;
      walletId = existing?.walletId ?? (w.isNotEmpty ? w.first.id : null);
      toWalletId =
          existing?.toWalletId ??
          (w.length > 1
              ? w[1].id
              : w.isNotEmpty
              ? w.first.id
              : null);
      categoryId = existing?.categoryId ?? _defaultCat(c, initialType);
      if (existing != null) {
        amountCtl.text = (existing.amountMillimes / 1000).toStringAsFixed(3);
        noteCtl.text = existing.note;
        when = existing.occurredAt;
      }
      loading = false;
    });
  }

  String _kindFor(String t) => t == 'income' ? 'income' : 'expense';

  String? _defaultCat(List<Category> c, String t) {
    final kind = _kindFor(t);
    final ofKind = c.where((e) => e.kind == kind).toList();
    if (ofKind.isEmpty) return c.isNotEmpty ? c.first.id : null;
    if (kind == 'income') {
      for (final want in ['inc_salary', 'inc_other_income']) {
        for (final cat in ofKind) {
          if (cat.nameKey == want) return cat.id;
        }
      }
      return ofKind.first.id;
    }
    for (final want in ['cat_cafe', 'cat_other']) {
      for (final cat in ofKind) {
        if (cat.nameKey == want) return cat.id;
      }
    }
    return ofKind.first.id;
  }

  /// Categories for the active type. While editing, the stored category is
  /// always offered even if its kind predates the income/expense split.
  List<Category> get _visibleCats {
    final kind = _kindFor(type);
    final list = cats.where((c) => c.kind == kind).toList();
    if (widget.editId != null &&
        categoryId != null &&
        !list.any((c) => c.id == categoryId)) {
      list.addAll(cats.where((c) => c.id == categoryId));
    }
    return list;
  }

  @override
  void dispose() {
    amountCtl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final lang = ref.read(languageProvider);
    setState(() => error = null);
    int amount;
    try {
      amount = Money.parse(amountCtl.text);
    } on FormatException {
      setState(() => error = Strings.get(lang, 'invalidAmount'));
      return;
    }
    if (walletId == null) {
      setState(() => error = Strings.get(lang, 'required'));
      return;
    }
    if (type == 'transfer' && (toWalletId == null || toWalletId == walletId)) {
      setState(() => error = Strings.get(lang, 'required'));
      return;
    }
    setState(() => saving = true);
    try {
      final repo = ref.read(transactionsRepoProvider);
      if (widget.editId != null) {
        await repo.updateTxn(
          widget.editId!,
          amountMillimes: amount,
          walletId: walletId,
          toWalletId: type == 'transfer' ? toWalletId : null,
          categoryId: type == 'transfer' ? null : categoryId,
          when: when,
          note: noteCtl.text,
        );
      } else if (type == 'expense') {
        await repo.addExpense(
          amountMillimes: amount,
          walletId: walletId!,
          categoryId: categoryId,
          when: when,
          note: noteCtl.text,
        );
      } else if (type == 'income') {
        await repo.addIncome(
          amountMillimes: amount,
          walletId: walletId!,
          categoryId: categoryId,
          when: when,
          note: noteCtl.text,
        );
      } else {
        await repo.addTransfer(
          amountMillimes: amount,
          fromWalletId: walletId!,
          toWalletId: toWalletId!,
          when: when,
          note: noteCtl.text,
        );
      }
      bumpRefresh(ref);
      Haptics.tap();
      // Refresh local alerts + home widget off the critical path.
      unawaited(ref.read(notifierProvider).replan(ref));
      unawaited(ref.read(masroufiWidgetProvider).refreshFrom(ref));
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final title = widget.editId != null
        ? Strings.get(lang, 'edit')
        : type == 'expense'
        ? Strings.get(lang, 'addExpense')
        : type == 'income'
        ? Strings.get(lang, 'addIncome')
        : Strings.get(lang, 'addTransfer');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loading
          ? const LoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      ButtonSegment(
                        value: 'transfer',
                        label: Text(Strings.get(lang, 'transfer')),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setState(() {
                      type = s.first;
                      // Never carry an expense category into income mode.
                      categoryId = _defaultCat(cats, type);
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Dominant amount: hero-sized, centered, numeric keyboard.
                  TextField(
                    controller: amountCtl,
                    autofocus: widget.editId == null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'amount'),
                      hintText: Strings.get(lang, 'amountHint'),
                      hintStyle: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      lang == 'ar' ? 'د.ت' : 'TND',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (type != 'transfer') ...[
                    const SizedBox(height: AppSpacing.md),
                    SectionHeader(
                      title: Strings.get(
                        lang,
                        type == 'income' ? 'incomeCategory' : 'category',
                      ),
                    ),
                    _templateRow(lang),
                    _recentRow(lang),
                    _categoryField(lang),
                    const SizedBox(height: AppSpacing.sm),
                    SectionHeader(
                      title: Strings.get(
                        lang,
                        type == 'income' ? 'moneyGoesTo' : 'payFrom',
                      ),
                    ),
                    _walletCards(lang, false),
                  ],
                  if (type == 'transfer') ...[
                    const SizedBox(height: AppSpacing.sm),
                    SectionHeader(title: Strings.get(lang, 'fromWallet')),
                    _walletCards(lang, false),
                    const SizedBox(height: AppSpacing.sm),
                    SectionHeader(title: Strings.get(lang, 'toWallet')),
                    _walletCards(lang, true),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: when,
                      );
                      if (picked != null) {
                        setState(() => when = picked);
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Strings.get(lang, 'date'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '${relativeDay(when, DateTime.now(), lang)} • ${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: noteCtl,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'note'),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        widget.editId != null
                            ? Strings.get(lang, 'save')
                            : title,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }

  /// Category field: tappable card showing the chosen subcategory over
  /// its primary ("☕ Café / Food & Drinks"). Opens the two-step
  /// primary → subcategory picker; stores the selected id unchanged.
  Widget _categoryField(String lang) {
    final byId = {for (final c in cats) c.id: c};
    final selected = categoryId == null ? null : byId[categoryId];
    final parentId = selected?.parentId;
    final parent = parentId == null ? null : byId[parentId];
    return AppCard(
      key: const ValueKey('categoryField'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      onTap: _pickCategory,
      child: Row(
        children: [
          CategoryAvatar(
            iconKey: selected?.icon,
            radius: 20,
            semanticLabel: selected == null
                ? Strings.get(lang, 'selectCategory')
                : Strings.categoryName(
                    lang,
                    selected.nameKey,
                    selected.customName,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: selected == null
                ? Text(
                    Strings.get(lang, 'selectCategory'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.categoryName(
                          lang,
                          selected.nameKey,
                          selected.customName,
                        ),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (parent != null)
                        Text(
                          Strings.categoryName(
                            lang,
                            parent.nameKey,
                            parent.customName,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
          ),
          Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// Template row: one tap prefills type/amount/wallet/category/note
  /// from a saved template (never writes by itself). Dangling wallet/
  /// category refs (deleted since saving) fall back to current picks.
  /// Long-press deletes the template (confirmed).
  Widget _templateRow(String lang) {
    return StreamBuilder(
      stream: ref.watch(templatesRepoProvider).watch(),
      builder: (context, snap) {
        final all = snap.data ?? const <TxnTemplate>[];
        final items = all.where((t) => t.type == type).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        final byId = {for (final c in cats) c.id: c};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.get(lang, 'templates'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in items)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: GestureDetector(
                        onLongPress: () async {
                          final ok = await confirmDialog(
                            context,
                            title: t.name,
                            body: Strings.get(lang, 'confirmDeleteBody'),
                            confirmLabel: Strings.get(lang, 'delete'),
                            cancelLabel: Strings.get(lang, 'cancel'),
                          );
                          if (ok) {
                            await ref
                                .read(templatesRepoProvider)
                                .remove(t.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    Strings.get(lang, 'templateDeleted'),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        },
                        child: ActionChip(
                          avatar: CategoryAvatar(
                            iconKey: t.categoryId == null
                                ? (t.type == 'transfer'
                                      ? 'transfer'
                                      : 'other')
                                : byId[t.categoryId]?.icon,
                            radius: 12,
                            semanticLabel: t.name,
                          ),
                          label: Text(t.name),
                          onPressed: () => _applyTemplate(t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }

  void _applyTemplate(TxnTemplate t) {
    final walletIds = {for (final w in wallets) w.id};
    final catIds = {for (final c in cats) c.id};
    setState(() {
      if (t.type == 'expense' || t.type == 'income' || t.type == 'transfer') {
        type = t.type;
      }
      amountCtl.text = (t.amountMillimes / 1000).toStringAsFixed(3);
      if (t.walletId != null && walletIds.contains(t.walletId)) {
        walletId = t.walletId;
      }
      if (t.toWalletId != null && walletIds.contains(t.toWalletId)) {
        toWalletId = t.toWalletId;
      }
      if (t.categoryId != null && catIds.contains(t.categoryId)) {
        categoryId = t.categoryId;
      }
      noteCtl.text = t.note;
    });
    Haptics.select();
  }

  /// Quick-add row: most-recently-used categories of the active type,
  /// straight from history (never invented). One tap selects; the full
  /// two-step picker stays available below. Hidden when history is empty.
  Widget _recentRow(String lang) {
    final visibleIds = _visibleCats.map((c) => c.id).toSet();
    final byId = {for (final c in cats) c.id: c};
    return FutureBuilder(
      future: ref
          .watch(transactionsRepoProvider)
          .recentCategoryIds(type: type, limit: 6),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final ids = snap.data!.where(visibleIds.contains).take(5).toList();
        // Don't echo the already-chosen category back at the user.
        ids.remove(categoryId);
        if (ids.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.get(lang, 'recentCategories'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final id in ids)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: ChoiceChip(
                        avatar: CategoryAvatar(
                          iconKey: byId[id]?.icon,
                          radius: 12,
                          semanticLabel: Strings.categoryName(
                            lang,
                            byId[id]?.nameKey,
                            byId[id]?.customName,
                          ),
                        ),
                        label: Text(
                          Strings.categoryName(
                            lang,
                            byId[id]?.nameKey,
                            byId[id]?.customName,
                          ),
                        ),
                        selected: false,
                        onSelected: (_) =>
                            setState(() => categoryId = id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPicker(
      context,
      lang: ref.read(languageProvider),
      visible: _visibleCats,
      byId: {for (final c in cats) c.id: c},
      selectedId: categoryId,
    );
    if (id != null && mounted) setState(() => categoryId = id);
  }

  /// Wallet destination/source cards with balances (masked when hidden).
  Widget _walletCards(String lang, bool isDestination) {
    final hideAll = ref.watch(hideBalancesProvider);
    final selected = isDestination ? toWalletId : walletId;
    final maskedLabel = Strings.get(lang, 'hiddenBalance');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < wallets.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) {
              final w = wallets[i];
              return WalletSelectCard(
                iconKey: w.icon,
                name: w.name,
                balanceMillimes: balances[w.id],
                masked: hideAll || w.isBalanceHidden,
                lang: lang,
                maskedLabel: maskedLabel,
                selected: selected == w.id,
                onTap: () => setState(() {
                  if (isDestination) {
                    toWalletId = w.id;
                  } else {
                    walletId = w.id;
                  }
                }),
              );
            },
          ),
        ],
      ],
    );
  }
}
