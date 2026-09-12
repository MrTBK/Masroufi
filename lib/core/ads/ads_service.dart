import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/brand.dart';

/// Central AdMob gate (P2/P3).
///
/// Rules (never change casually):
/// - Ads load automatically for everyone post-onboarding with internet:
///   no opt-in tap needed. Consent switch tunes personalization only.
/// - No ads before onboarding, on lock, PRO, or in money-entry (`/add`).
/// - Interstitial max 1 per 10 minutes, only after success moments
///   (PDF export, backup). Silent skip when not loaded / offline / PRO.
/// - Never logs amounts, notes, category names, or wallet names.
/// - All methods are best-effort: any failure returns null/false and the
///   finance flow continues. Fully test-mockable via [AdsGate].
abstract final class AdsGate {
  /// True when ads may load: onboarding done, not PRO. Personalization
  /// is a separate flag applied per request, never a load gate.
  static bool canLoad({
    required bool isPro,
    required bool onboardingDone,
  }) => !isPro && onboardingDone;

  /// Frequency cap for interstitials.
  static bool interstitialDue(DateTime? lastShown, DateTime now) {
    if (lastShown == null) return true;
    return now.difference(lastShown).inMinutes >= 10;
  }
}

/// Runtime ad state. Kept in a Riverpod StateProvider as last-shown time;
/// the service itself holds loaded ad instances (disposed on use).
class AdsService {
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _initDone = false;

  /// Initialize MobileAds once. Never throws; offline/startup safe.
  Future<void> ensureInitialized() async {
    if (_initDone) return;
    try {
      // UMP consent is requested separately in main() via
      // UserMessagingPlatform; init proceeds regardless so test ads
      // still work when consent flow is unavailable (desktop/tests).
      await MobileAds.instance.initialize();
      _initDone = true;
    } catch (_) {
      // Offline or missing platform: ads stay disabled, app usable.
      _initDone = false;
    }
  }

  /// Preload interstitial for post-export moments.
  Future<void> preloadInterstitial() async {
    try {
      await InterstitialAd.load(
        adUnitId: Brand.interstitialExportId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitial = ad,
          onAdFailedToLoad: (_) => _interstitial = null,
        ),
      );
    } catch (_) {
      _interstitial = null;
    }
  }

  /// Show preloaded interstitial if ready + cap allows. Returns true
  /// when an ad was shown (caller updates last-shown time).
  Future<bool> showInterstitialIfReady({
    required bool isPro,
    required bool onboardingDone,
    required DateTime? lastShown,
    required DateTime now,
  }) async {
    if (!AdsGate.canLoad(isPro: isPro, onboardingDone: onboardingDone)) {
      return false;
    }
    if (!AdsGate.interstitialDue(lastShown, now)) return false;
    final ad = _interstitial;
    if (ad == null) {
      // Opportunistic reload for next time; never blocks caller.
      unawaited(preloadInterstitial());
      return false;
    }
    try {
      _interstitial = null;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) => a.dispose(),
        onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
      );
      await ad.show();
      unawaited(preloadInterstitial());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Preload rewarded for unlock moments (XLSX, AI explain, year share).
  Future<void> preloadRewarded() async {
    try {
      await RewardedAd.load(
        adUnitId: Brand.rewardedUnlockId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _rewarded = ad,
          onAdFailedToLoad: (_) => _rewarded = null,
        ),
      );
    } catch (_) {
      _rewarded = null;
    }
  }

  /// Show rewarded; [onReward] runs only when the user earns it.
  /// Returns true when reward was earned.
  Future<bool> showRewarded({
    required bool isPro,
    required bool onboardingDone,
    required void Function() onReward,
  }) async {
    // PRO users unlock directly without watching.
    if (isPro) {
      onReward();
      return true;
    }
    if (!AdsGate.canLoad(isPro: isPro, onboardingDone: onboardingDone)) {
      return false;
    }
    final ad = _rewarded;
    if (ad == null) {
      unawaited(preloadRewarded());
      return false;
    }
    var earned = false;
    try {
      _rewarded = null;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) => a.dispose(),
        onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
      );
      await ad.show(
        onUserEarnedReward: (adWithoutView, reward) {
          earned = true;
          onReward();
        },
      );
      unawaited(preloadRewarded());
      return earned;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    try {
      _interstitial?.dispose();
    } catch (_) {}
    try {
      _rewarded?.dispose();
    } catch (_) {}
    _interstitial = null;
    _rewarded = null;
  }
}
