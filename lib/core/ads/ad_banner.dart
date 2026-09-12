import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app/providers.dart';
import '../config/brand.dart';

/// Adaptive banner slot (P2).
///
/// - Loads automatically post-onboarding with internet (no opt-in tap).
///   Consent switch tunes personalization, never loading.
/// - Collapses to zero height offline / PRO / load failure.
/// - Never placed on onboarding, lock, or `/add` money-entry.
/// - Fixed 50dp + SafeArea so money buttons never shift unexpectedly.
class AdBanner extends ConsumerStatefulWidget {
  final String slot; // 'dashboard' | 'reports'
  const AdBanner({super.key, required this.slot});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _ready = false;

  String get _unitId => widget.slot == 'reports'
      ? Brand.bannerReportsId
      : Brand.bannerDashboardId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  Future<void> _tryLoad() async {
    final isPro = ref.read(isProProvider);
    final done = ref.read(onboardingDoneProvider);
    if (isPro || !done) return;
    final consent = ref.read(adsConsentProvider);
    try {
      final ad = BannerAd(
        adUnitId: _unitId,
        size: AdSize.banner,
        request: AdRequest(nonPersonalizedAds: !consent),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _ready = true);
          },
          onAdFailedToLoad: (a, _) {
            a.dispose();
            if (mounted) setState(() => _ready = false);
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    try {
      _ad?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reactive collapse: toggling PRO hides immediately.
    final isPro = ref.watch(isProProvider);
    final done = ref.watch(onboardingDoneProvider);
    if (isPro || !done || !_ready || _ad == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: _ad!.size.width.toDouble(),
            height: _ad!.size.height.toDouble(),
            child: AdWidget(ad: _ad!),
          ),
        ),
      ),
    );
  }
}
