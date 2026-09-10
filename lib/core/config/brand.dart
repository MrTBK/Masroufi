/// Centralized branding. Change the name here to rebrand the app.
abstract final class Brand {
  static const String nameEn = 'Masroufi';
  static const String nameAr = 'مصروفي';
  static const String nameFr = 'Masroufi';
  static const String applicationId = 'com.masroufi.app';
  static const String currencyCode = 'TND';

  static String nameFor(String lang) => switch (lang) {
    'ar' => nameAr,
    'fr' => nameFr,
    _ => nameEn,
  };

  // ---- Ads (AdMob) + PRO ----
  // Prod IDs arrive via --dart-define so real IDs never commit.
  // Debug/test builds fall back to Google test IDs.
  static const String adAppId = String.fromEnvironment(
    'ADS_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );
  static const String bannerDashboardId = String.fromEnvironment(
    'ADS_BANNER_DASHBOARD',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String bannerReportsId = String.fromEnvironment(
    'ADS_BANNER_REPORTS',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String interstitialExportId = String.fromEnvironment(
    'ADS_INTERSTITIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const String rewardedUnlockId = String.fromEnvironment(
    'ADS_REWARDED',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );
  static const String proRemoveAdsSku = 'masroufi_pro_2026';

  /// True when running with Google test IDs (debug default).
  static bool get usingTestAds => adAppId.contains('3940256099942544');
}
