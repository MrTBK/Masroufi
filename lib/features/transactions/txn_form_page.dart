import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';

/// Add or edit expense/income/transfer. Optimized for speed:
/// amount (autofocus, numeric) -> category -> wallet -> save.
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

  @override
  void initState() {
    super.initState();
    type = ['expense', 'income', 'transfer'].contains(widget.initialType)
        ? widget.initialType
        : 'expense';
    _load();
  }

  Future<void> _load() async {
    final w = await ref.read(walletsRepoProvider).all(includeArchived: false);
    final c = await ref
        .read(categoriesRepoProvider)
        .all(includeArchived: false);
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
    setState(() {
      wallets = w;
      cats = c;
      walletId = existing?.walletId ?? (w.isNotEmpty ? w.first.id : null);
      toWalletId =
          existing?.toWalletId ??
          (w.length > 1
              ? w[1].id
              : w.isNotEmpty
              ? w.first.id
              : null);
      categoryId = existing?.categoryId ?? _defaultCat(c);
      if (existing != null) {
        type = existing.type;
        amountCtl.text = (existing.amountMillimes / 1000).toStringAsFixed(3);
        noteCtl.text = existing.note;
        when = existing.occurredAt;
      }
      loading = false;
    });
  }

  String? _defaultCat(List<Category> c) {
    for (final want in ['cat_cafe', 'cat_other']) {
      for (final cat in c) {
        if (cat.nameKey == want) return cat.id;
      }
    }
    return c.isNotEmpty ? c.first.id : null;
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
              padding: const EdgeInsets.all(16),
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
                    onSelectionChanged: (s) => setState(() => type = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'amount'),
                      hintText: Strings.get(lang, 'amountHint'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (type != 'transfer')
                    DropdownButtonFormField<String>(
                      initialValue: categoryId,
                      decoration: InputDecoration(
                        labelText: Strings.get(lang, 'category'),
                      ),
                      items: [
                        for (final c in cats)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              Strings.categoryName(
                                lang,
                                c.nameKey,
                                c.customName,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                  if (type != 'transfer') const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: walletId,
                    decoration: InputDecoration(
                      labelText: type == 'transfer'
                          ? Strings.get(lang, 'fromWallet')
                          : Strings.get(lang, 'wallet'),
                    ),
                    items: [
                      for (final w in wallets)
                        DropdownMenuItem(value: w.id, child: Text(w.name)),
                    ],
                    onChanged: (v) => setState(() => walletId = v),
                  ),
                  if (type == 'transfer') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: toWalletId,
                      decoration: InputDecoration(
                        labelText: Strings.get(lang, 'toWallet'),
                      ),
                      items: [
                        for (final w in wallets)
                          DropdownMenuItem(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: (v) => setState(() => toWalletId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: Text(Strings.get(lang, 'date')),
                    subtitle: Text(
                      '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: when,
                      );
                      if (picked != null) setState(() => when = picked);
                    },
                  ),
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
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(Strings.get(lang, 'save')),
                  ),
                ],
              ),
            ),
    );
  }
}
