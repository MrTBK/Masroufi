import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/providers.dart';
import '../analytics/bi_scope.dart';
import '../analytics/insights.dart';
import '../l10n/strings.dart';
import '../money/money.dart';
import '../theme/app_theme.dart';
import '../widgets/design.dart';
import 'ai_gateway.dart';
import 'ai_summary.dart';

/// "Explain this scope" bottom sheet (P4).
///
/// Tiered content (always useful, even offline):
/// 1. On-device factual insights (existing [Insights] engine) — free.
/// 2. Cloud explanation via [AiGateway] — only when opted in + online.
///    PRO users get priority quota; free users may unlock one via
///    rewarded ad. Disclaimer always shown: planning aid, not advice.
Future<void> showAiExplain({
  required BuildContext context,
  required WidgetRef ref,
  required BiSnapshot snapshot,
}) async {
  final lang = ref.read(languageProvider);
  final aiOn = ref.read(aiCloudProvider);
  final isPro = ref.read(isProProvider);
  final includeNotes = ref.read(aiNotesProvider);
  final summaryJson = AiSummaryBuilder.encode(
    snapshot,
    lang: lang,
    includeNotes: includeNotes,
  );

  // On-device lines first (never empty-network dependent).
  final byId = {for (final c in snapshot.cats) c.id: c};
  String? topName;
  var topVal = 0;
  snapshot.byCategory.forEach((id, v) {
    if (v > topVal) {
      topVal = v;
      topName = id == null ? '—' : (byId[id]?.customName ?? id);
    }
  });
  final offlineLines = Insights.buildInsights(
    currentExpense: snapshot.expense,
    previousExpense: snapshot.prevByCat.values.fold(0, (a, b) => a + b),
    topCatName: topName,
    funSharePct: null,
    incomeMoM: null,
    dailyAvgFormatted: snapshot.txnCount > 0
        ? Money.inline(snapshot.expense ~/ snapshot.txnCount, lang: lang)
        : null,
    lang: lang,
  );
  final forecastLine = Strings.tpl(lang, 'aiForecastLine', {
    'v': Money.inline(snapshot.forecastProjected, lang: lang),
    'p': '${snapshot.forecastPacePct}',
  });

  String? cloudText;
  var cloudLoading = aiOn;
  var cloudError = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (c, setSheet) {
        Future<void> loadCloud() async {
          setSheet(() {
            cloudLoading = true;
            cloudError = false;
          });
          final text = await AiGateway().explain(
            summaryJson: summaryJson,
            lang: lang,
            isPro: isPro,
          );
          if (c.mounted) {
            setSheet(() {
              cloudLoading = false;
              if (text == null) {
                cloudError = true;
              } else {
                cloudText = text;
              }
            });
          }
        }

        // Auto-load once when opened with opt-in.
        if (aiOn && cloudText == null && !cloudError && cloudLoading) {
          Future.microtask(loadCloud);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          Strings.get(lang, 'aiExplainTitle'),
                          style: Theme.of(c).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(c),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final line in offlineLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(line)),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(forecastLine)),
                      ],
                    ),
                  ),
                  const Divider(height: AppSpacing.lg),
                  if (!aiOn) ...[
                    Text(Strings.get(lang, 'aiOptInBody')),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      onPressed: () async {
                        await ref
                            .read(settingsRepoProvider)
                            .setAiCloudEnabled(true);
                        ref.read(aiCloudProvider.notifier).state = true;
                        setSheet(() => cloudLoading = true);
                        await loadCloud();
                      },
                      child: Text(Strings.get(lang, 'aiOptIn')),
                    ),
                  ] else if (cloudLoading) ...[
                    const Center(child: CircularProgressIndicator()),
                  ] else if (cloudText != null) ...[
                    AppCard(child: SelectableText(cloudText!)),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: cloudText!),
                            );
                          },
                          child: Text(Strings.get(lang, 'copy')),
                        ),
                        TextButton(
                          onPressed: loadCloud,
                          child: Text(Strings.get(lang, 'aiRegenerate')),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(Strings.get(lang, 'aiOfflineFallback')),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () async {
                        // Free users: rewarded ad unlocks one cloud call
                        // when PRO quota is unavailable.
                        final ok = await ref
                            .read(adsServiceProvider)
                            .showRewarded(
                              consentGiven: ref.read(adsConsentProvider),
                              isPro: isPro,
                              onboardingDone: ref.read(onboardingDoneProvider),
                              onReward: () {},
                            );
                        if (ok || isPro) await loadCloud();
                      },
                      child: Text(Strings.get(lang, 'aiUnlockCloud')),
                    ),
                    if (cloudError)
                      TextButton(
                        onPressed: loadCloud,
                        child: Text(Strings.get(lang, 'aiRetry')),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    Strings.get(lang, 'aiDisclaimer'),
                    style: Theme.of(c).textTheme.bodySmall?.copyWith(
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
