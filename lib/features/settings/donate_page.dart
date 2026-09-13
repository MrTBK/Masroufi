import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/promos/promos.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';

/// Donations (Tunisia): D17 + Ba9chich, copy-to-clipboard, zero new
/// deps. No tracking, no amounts leave the device.
class DonatePage extends ConsumerStatefulWidget {
  const DonatePage({super.key});

  @override
  ConsumerState<DonatePage> createState() => _DonatePageState();
}

class _DonatePageState extends ConsumerState<DonatePage> {
  /// Connectivity checked once on open: null while checking, false when
  /// offline (ads unavailable), true when online (preload + show).
  bool? _online;

  @override
  void initState() {
    super.initState();
    _checkOnce();
  }

  Future<void> _checkOnce() async {
    // Warm the rewarded slot on open when online: startup preload may
    // have missed (offline at launch), and without this the first tap
    // always fails. Offline: skip preload, ads cannot load anyway.
    final online = await ref.read(onlineCheckProvider)();
    if (!mounted) return;
    setState(() => _online = online);
    if (online) {
      await ref.read(adsServiceProvider).preloadRewarded();
    }
  }

  Future<void> _copy(BuildContext context, WidgetRef ref, String text) async {
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      final lang = ref.read(languageProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Strings.get(lang, 'saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final scheme = Theme.of(context).colorScheme;
    final offline = _online == false;
    final isPro = ref.watch(isProProvider);
    // Paid promo of the day; null while registry empty (house invite
    // card shows instead). PRO hides the slot entirely.
    final promo = isPro ? null : Promos.pickFor(DateTime.now());
    final showInvite = !isPro && promo == null;
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'donate'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(
                    Icons.volunteer_activism,
                    size: 28,
                    semanticLabel: 'donate',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, 'donateTitle'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        Strings.get(lang, 'donateBody'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            label: Text(Strings.get(lang, 'donateWatch')),
            onPressed: () async {
              Haptics.tap();
              if (offline) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(Strings.get(lang, 'donateOffline'))),
                );
                return;
              }
              final ok = await ref
                  .read(adsServiceProvider)
                  .showRewarded(
                    isPro: ref.read(isProProvider),
                    onboardingDone: ref.read(onboardingDoneProvider),
                    onReward: () {},
                  );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    Strings.get(lang, ok ? 'donateThanks' : 'donateAdNotReady'),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: Strings.get(lang, 'donateOffline'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      Strings.get(lang, 'donateOffline'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          if (!isPro && (showInvite || promo != null))
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Icon(
                      promo == null ? Icons.campaign : Icons.storefront,
                      size: 22,
                      semanticLabel: promo == null
                          ? Strings.get(lang, 'promoInviteTitle')
                          : Strings.get(lang, promo.titleKey),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promo == null
                              ? Strings.get(lang, 'promoInviteTitle')
                              : Strings.get(lang, promo.titleKey),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          promo == null
                              ? Strings.get(lang, 'promoInviteBody')
                              : Strings.get(lang, promo.bodyKey),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            promo?.link ?? Brand.proWhatsApp,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: Strings.get(lang, 'proCopy'),
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () =>
                        _copy(context, ref, promo?.link ?? Brand.proWhatsApp),
                  ),
                ],
              ),
            ),
          if (!isPro && (showInvite || promo != null))
            const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                for (final k in ['donateWhy1', 'donateWhy2', 'donateWhy3'])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 20,
                          color: AppColors.expense,
                          semanticLabel: Strings.get(lang, k),
                        ),
                        const SizedBox(width: AppSpacing.md2),
                        Expanded(
                          child: Text(
                            Strings.get(lang, k),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(
                    Icons.smartphone,
                    size: 22,
                    semanticLabel: 'D17',
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'D17',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          Brand.proD17Number,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: Strings.get(lang, 'proCopy'),
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, ref, Brand.proD17Number),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(
                    Icons.volunteer_activism,
                    size: 22,
                    semanticLabel: 'Ba9chich',
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Text(
                    'Ba9chich',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: Strings.get(lang, 'proCopyLink'),
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, ref, Brand.ba9chichUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
