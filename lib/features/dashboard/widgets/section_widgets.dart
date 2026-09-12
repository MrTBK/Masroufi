part of '../dashboard_page.dart';

/// Budget vs actual anchored to the snapshot month: overall plus every
/// per-category row, all through the shared BudgetBar.
class _BudgetVsActual extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _BudgetVsActual({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    if (s.overallBudget == null && s.budgetRows.isEmpty) {
      return const SizedBox.shrink();
    }
    final byId = {for (final c in s.cats) c.id: c};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'budgetVsActual')),
        if (s.overallBudget != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.get(lang, 'budget'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                BudgetBar(
                  spentMillimes: s.overallSpent,
                  totalMillimes: s.overallBudget!,
                  lang: lang,
                ),
              ],
            ),
          ),
        if (s.overallBudget != null && s.budgetRows.isNotEmpty)
          const SizedBox(height: AppSpacing.sm),
        for (final r in s.budgetRows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  byId[r.categoryId] == null
                      ? '—'
                      : CategoryHierarchy.displayName(
                          lang,
                          byId[r.categoryId]!,
                          byId,
                        ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                BudgetBar(
                  spentMillimes: r.spent,
                  totalMillimes: r.budget,
                  lang: lang,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

/// Scope export row: KPI summary CSV, filtered dataset CSV (capped,
/// documented), and a statement PDF for the scope-end month with the
/// filtered numbers. Same save-sheet pattern as backup (BOM for Excel).
class _ExportRow extends ConsumerWidget {
  final String lang;
  final BiSnapshot s;
  const _ExportRow({required this.lang, required this.s});

  Future<void> _save(
    BuildContext context,
    String fileName,
    String content,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString('\uFEFF$content');
    await FilePicker.saveFile(fileName: fileName, bytes: await f.readAsBytes());
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Strings.get(lang, 'saved'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome, size: 20),
          label: Text(Strings.get(lang, 'aiExplain')),
          onPressed: () =>
              showAiExplain(context: context, ref: ref, snapshot: s),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.summarize_outlined, size: 20),
          label: Text(Strings.get(lang, 'exportKpiCsv')),
          onPressed: () => _save(
            context,
            'masroufi_kpi_${s.to.year}-${s.to.month.toString().padLeft(2, '0')}.csv',
            BiExport.kpiCsv(s),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
          label: Text(Strings.get(lang, 'exportWalletCsv')),
          onPressed: () => _save(
            context,
            'masroufi_wallets_${s.to.year}-${s.to.month.toString().padLeft(2, '0')}.csv',
            BiExport.walletFlowsCsv(s),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_chart_outlined, size: 20),
          label: Text(Strings.get(lang, 'exportDataCsv')),
          onPressed: () async {
            final filter = ref.read(biFilterProvider);
            final repo = ref.read(transactionsRepoProvider);
            final txns = await repo.list(
              TxnFilter(
                walletIds: filter.walletIds.isEmpty ? null : filter.walletIds,
                categoryIds: filter.categoryIds,
                type: filter.type,
                from: filter.from,
                to: filter.to,
                // Analytical sample cap (documented): full history stays
                // in backup JSON; CSV is the working slice.
                limit: 2000,
              ),
            );
            final db = ref.read(appDbProvider);
            final wallets = {
              for (final w in await db.select(db.wallets).get()) w.id: w,
            };
            final cats = {
              for (final c in await db.select(db.categories).get()) c.id: c,
            };
            if (!context.mounted) return;
            await _save(
              context,
              'masroufi_data_${s.to.year}-${s.to.month.toString().padLeft(2, '0')}.csv',
              BiExport.datasetCsv(
                txns: txns,
                wallets: wallets,
                cats: cats,
                lang: lang,
              ),
            );
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          label: Text(Strings.get(lang, 'exportPdf')),
          onPressed: () async {
            final data = MonthlyStatementBuilder.build(
              year: s.to.year,
              month: s.to.month,
              incomeMillimes: s.income,
              expenseMillimes: s.expense,
              txnCount: s.txnCount,
              byCategory: s.byCategory,
              categoryNames: {
                for (final e in s.byCategory.keys.whereType<String>())
                  e: _catName(lang, s.cats, e),
              },
            );
            ByteData? font;
            try {
              font = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
            } catch (_) {
              font = null;
            }
            final bytes = await MonthlyStatementBuilder.buildPdf(
              data: data,
              lang: lang,
              arabicFont: font,
            );
            final dir = await getApplicationDocumentsDirectory();
            final name =
                'masroufi_statement_${s.to.year}-${s.to.month.toString().padLeft(2, '0')}.pdf';
            final f = File('${dir.path}/$name');
            await f.writeAsBytes(bytes);
            await FilePicker.saveFile(
              fileName: name,
              bytes: await f.readAsBytes(),
            );
          },
        ),
      ],
    );
  }
}

/// Transparent health score: hero number plus every input with its
/// points and weight, missing inputs flagged, debt facts alongside.
class _HealthSection extends StatelessWidget {
  final String lang;
  final BiSnapshot s;
  const _HealthSection({required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final util = Kpi.budgetUtilization(
      spentMillimes: s.overallSpent,
      budgetMillimes: s.overallBudget,
    );
    final h = Kpi.healthScore(
      savingsRatePct: s.savingsRate,
      budgetUtilizationPct: util,
      expenseGrowthPct: s.growth?.pct,
      obligationsSharePct: s.obligationsShare,
    );
    String inputLabel(String key) => switch (key) {
      'savings' => Strings.get(lang, 'savingsRate'),
      'adherence' => Strings.get(lang, 'budgetAdherence'),
      'growth' => Strings.get(lang, 'expenseGrowth'),
      _ => Strings.get(lang, 'recurringShare'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: Strings.get(lang, 'healthScore')),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${h.score}',
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      Strings.get(
                        lang,
                        h.band == 'strong'
                            ? 'healthStrong'
                            : h.band == 'steady'
                            ? 'healthSteady'
                            : 'healthStrained',
                      ),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final i in h.inputs) ...[
                Row(
                  children: [
                    Expanded(child: Text(inputLabel(i.key))),
                    Text(
                      '${i.points}/100 · ${i.weight}%',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (h.missing.contains(i.key))
                  Text(
                    Strings.get(lang, 'insufficientData'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
              if (s.openOwed > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: Text(Strings.get(lang, 'openDebts'))),
                    MoneyText(
                      millimes: s.openOwed,
                      lang: lang,
                      type: 'neutral',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
              if (s.overdueDebts > 0)
                Text(
                  '${Strings.get(lang, 'overdue')}: ${s.overdueDebts}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
