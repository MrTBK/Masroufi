import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/providers.dart';
import '../../core/ads/pro_service.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';

/// PRO paywall: remove ads + unlock AI quota + advanced BI export.
///
/// Two paths: Play Billing (when store available) + manual activation
/// code for Tunisia (e-Dinar/cash, offline HMAC). Purchase completion
/// listens to `purchaseStream`; manual code verifies instantly.
class ProPage extends ConsumerStatefulWidget {
  const ProPage({super.key});
  @override
  ConsumerState<ProPage> createState() => _ProPageState();
}

class _ProPageState extends ConsumerState<ProPage> {
  final codeCtl = TextEditingController();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? product;
  bool loadingProduct = true;
  String? msg;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadProduct();
    // No store on desktop/tests: guard, manual-code path stays usable.
    try {
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
      );
    } catch (_) {
      _sub = null;
    }
  }

  Future<void> _loadProduct() async {
    final p = await ProService.queryProProduct();
    if (mounted) {
      setState(() {
        product = p;
        loadingProduct = false;
      });
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    final lang = ref.read(languageProvider);
    for (final p in list) {
      if (p.productID !=
          // ignore: avoid_hardcoded (SKU defined in Brand)
          'masroufi_pro_2026') {
        continue;
      }
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        try {
          await ref.read(settingsRepoProvider).setPro(true);
        } catch (_) {}
        ref.read(isProProvider.notifier).state = true;
        if (mounted) {
          setState(() => msg = Strings.get(lang, 'proThanks'));
        }
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    codeCtl.dispose();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'proTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: const Icon(
                    Icons.workspace_premium,
                    size: 28,
                    semanticLabel: 'PRO',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, 'proBenefits'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          Brand.proPriceLabel,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
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
            child: Column(
              children: [
                for (final k in ['proWhy1', 'proWhy2', 'proWhy3'])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 20,
                          color: AppColors.income,
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
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Strings.get(lang, 'proBenefitsBody'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isPro)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(Strings.get(lang, 'proThanks'))),
                ],
              ),
            )
          else ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (loadingProduct)
                    const Center(child: CircularProgressIndicator())
                  else if (product != null)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await ProService.buyPro(product!);
                              } finally {
                                if (mounted) {
                                  setState(() => busy = false);
                                }
                              }
                            },
                      child: Text(
                        '${Strings.get(lang, 'proBuy')} • ${product!.price}',
                      ),
                    )
                  else
                    Text(
                      Strings.get(lang, 'proStoreUnavailable'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await InAppPurchase.instance.restorePurchases();
                            } catch (_) {}
                          },
                    child: Text(Strings.get(lang, 'proRestore')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _PaySection(),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Strings.get(lang, 'proManualTitle'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (ProService.proPin.isEmpty &&
                      ProService.manualSecret.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        Strings.get(lang, 'proManualDisabled'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: codeCtl,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'proManualHint'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () async {
                      final langNow = ref.read(languageProvider);
                      // Single-device binding: code must match this install.
                      final deviceId = await ref
                          .read(settingsRepoProvider)
                          .installId();
                      final ok = ProService.verifyManualCode(
                        codeCtl.text,
                        deviceId,
                      );
                      if (ok) {
                        try {
                          await ref.read(settingsRepoProvider).setPro(true);
                        } catch (_) {}
                        ref.read(isProProvider.notifier).state = true;
                        if (mounted) {
                          setState(
                            () => msg = Strings.get(langNow, 'proThanks'),
                          );
                        }
                      } else {
                        if (mounted) {
                          setState(
                            () =>
                                msg = Strings.get(langNow, 'proManualInvalid'),
                          );
                        }
                      }
                    },
                    child: Text(Strings.get(lang, 'proActivate')),
                  ),
                ],
              ),
            ),
          ],
          if (msg != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(msg!),
          ],
        ],
      ),
    );
  }
}

/// Pay with D17 or Ba9chich (Tunisia): fixed 9.9 DT, proof over
/// WhatsApp. Zero new deps: everything copies to clipboard, the buyer
/// sends the screenshot + ref from their own chat app, the code comes
/// back the same way and pastes into the manual box above.
class _PaySection extends ConsumerWidget {
  const _PaySection();

  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    String text,
  ) async {
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      final lang = ref.read(languageProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.get(lang, 'saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: Strings.get(lang, 'proPayTitle')),
        Text(
          Strings.get(lang, 'proPayBody'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<String>(
          future: ref.watch(settingsRepoProvider).installId(),
          builder: (context, snap) {
            final id = snap.data ?? '';
            final short = id.length >= 8
                ? id.substring(0, 8).toUpperCase()
                : '…';
            final msg = 'Masroufi PRO ${Brand.proPriceLabel} ref $short';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                                '${Brand.proD17Number} • ${Brand.proPriceLabel}',
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
                            _copy(context, ref, Brand.proD17Number),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ba9chich',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '10 Diamonds',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: Strings.get(lang, 'proCopyLink'),
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () =>
                            _copy(context, ref, Brand.ba9chichUrl),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${Strings.get(lang, 'proMyRef')}: $short',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: Strings.get(lang, 'proCopyRef'),
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () => _copy(context, ref, short),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: Text(Strings.get(lang, 'proCopyMsg')),
                        onPressed: () => _copy(context, ref, msg),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
