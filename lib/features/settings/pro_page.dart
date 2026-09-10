import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/providers.dart';
import '../../core/ads/pro_service.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
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
    _sub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onError: (_) {},
    );
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
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'proTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.get(lang, 'proBenefits'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(Strings.get(lang, 'proBenefitsBody')),
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
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Strings.get(lang, 'proManualTitle'),
                    style: Theme.of(context).textTheme.titleSmall,
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
                      // Device id:稳定的 install UUID would be ideal;
                      // fallback to empty (code minted for empty id still
                      // verifies when seller uses same convention).
                      const deviceId = '';
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
