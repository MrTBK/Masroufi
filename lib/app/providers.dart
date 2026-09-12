import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ads/ads_service.dart';
import '../core/analytics/bi_scope.dart';
import '../data/database/app_db.dart';
import '../data/repositories/analytics_repo.dart';
import '../data/repositories/budgets_repo.dart';
import '../data/repositories/categories_repo.dart';
import '../data/repositories/category_budgets_repo.dart';
import '../data/repositories/debts_repo.dart';
import '../data/repositories/recurring_repo.dart';
import '../data/repositories/savings_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../data/repositories/splits_repo.dart';
import '../data/repositories/templates_repo.dart';
import '../data/repositories/transactions_repo.dart';
import '../data/repositories/wallets_repo.dart';

final appDbProvider = Provider<AppDb>((ref) => throw UnimplementedError());

final walletsRepoProvider = Provider<WalletsRepo>(
  (ref) => WalletsRepo(ref.watch(appDbProvider)),
);
final categoriesRepoProvider = Provider<CategoriesRepo>(
  (ref) => CategoriesRepo(ref.watch(appDbProvider)),
);
final transactionsRepoProvider = Provider<TransactionsRepo>(
  (ref) => TransactionsRepo(ref.watch(appDbProvider)),
);
final analyticsRepoProvider = Provider<AnalyticsRepo>(
  (ref) => AnalyticsRepo(ref.watch(appDbProvider)),
);
final budgetsRepoProvider = Provider<BudgetsRepo>(
  (ref) => BudgetsRepo(ref.watch(appDbProvider)),
);
final recurringRepoProvider = Provider<RecurringRepo>(
  (ref) => RecurringRepo(ref.watch(appDbProvider)),
);
final categoryBudgetsRepoProvider = Provider<CategoryBudgetsRepo>(
  (ref) => CategoryBudgetsRepo(ref.watch(appDbProvider)),
);
final savingsRepoProvider = Provider<SavingsRepo>(
  (ref) => SavingsRepo(ref.watch(appDbProvider)),
);
final debtsRepoProvider = Provider<DebtsRepo>(
  (ref) => DebtsRepo(ref.watch(appDbProvider)),
);
final settingsRepoProvider = Provider<SettingsRepo>(
  (ref) => SettingsRepo(ref.watch(appDbProvider)),
);
final templatesRepoProvider = Provider<TemplatesRepo>(
  (ref) => TemplatesRepo(ref.watch(appDbProvider)),
);
final splitsRepoProvider = Provider<SplitsRepo>(
  (ref) => SplitsRepo(ref.watch(appDbProvider)),
);

/// UI state (persisted to app_settings on change by settings page/onboarding).
final languageProvider = StateProvider<String>((ref) => 'en');
final themeNameProvider = StateProvider<String>((ref) => 'light');
final onboardingDoneProvider = StateProvider<bool>((ref) => false);

/// Global balance-privacy switch (display-only; math never reads this).
final hideBalancesProvider = StateProvider<bool>((ref) => false);

/// First day of the week for analytics periods (monday|sunday|saturday).
/// Persisted to app_settings; defaults to Monday.
final weekStartProvider = StateProvider<String>((ref) => 'monday');

/// Dashboard analytics period selector
/// (thisWeek|lastWeek|thisMonth|lastMonth|last3Months|year). Drives every
/// period-scoped dashboard aggregate (income, expenses, net, spending).
/// Legacy 'week'/'month' values from older prefs map to thisWeek/thisMonth.
final dashPeriodProvider = StateProvider<String>((ref) => 'thisMonth');

/// Normalized dashboard period (migrates legacy week/month ids).
String normalizedDashPeriod(String raw) => switch (raw) {
  'week' => 'thisWeek',
  'month' => 'thisMonth',
  _ => raw,
};

/// Bumped to refresh dashboard aggregates after mutations.
final refreshTickProvider = StateProvider<int>((ref) => 0);
void bumpRefresh(WidgetRef ref) =>
    ref.read(refreshTickProvider.notifier).state++;

/// Calendar month pager (Track 3): which month the dashboard spending
/// calendar shows. Defaults to the current month; chevrons move ±1 month.
final calMonthProvider = StateProvider<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month, 1),
);

/// Rollover opt-in (Track 6, display-only). Persisted to settings KV.
final rolloverProvider = StateProvider<bool>((ref) => false);

/// BI filter bar selection. Defaults to the current calendar month
/// (half-open [monthStart, nextMonth)); presets rewrite it wholesale.
BiFilter _defaultBiFilter() {
  final now = DateTime.now();
  return BiFilter(
    from: DateTime(now.year, now.month, 1),
    to: now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1),
  );
}

final biFilterProvider = StateProvider<BiFilter>((ref) => _defaultBiFilter());

/// BI engine assembled from the existing repositories (no new data
/// layer; see FilteredAnalytics).
final filteredAnalyticsProvider = Provider<FilteredAnalytics>(
  (ref) => FilteredAnalytics(
    analytics: ref.watch(analyticsRepoProvider),
    wallets: ref.watch(walletsRepoProvider),
    categories: ref.watch(categoriesRepoProvider),
    recurring: ref.watch(recurringRepoProvider),
    debts: ref.watch(debtsRepoProvider),
    budgets: ref.watch(budgetsRepoProvider),
    catBudgets: ref.watch(categoryBudgetsRepoProvider),
  ),
);

/// The single snapshot every Analytics visualization reads. Reloads on
/// filter change and on [refreshTickProvider] bumps after mutations.
final biSnapshotProvider = FutureProvider<BiSnapshot>((ref) async {
  ref.watch(refreshTickProvider);
  final filter = ref.watch(biFilterProvider);
  return ref.watch(filteredAnalyticsProvider).load(filter);
});

// ---- Ads + AI + PRO state (P2-P4, persisted via SettingsRepo) ----
/// Personalized-ads consent (default off). Persisted `ads_consent`.
final adsConsentProvider = StateProvider<bool>((ref) => false);

/// PRO remove-ads entitlement (default off). Persisted `is_pro`.
final isProProvider = StateProvider<bool>((ref) => false);

/// Cloud-AI opt-in + notes flag (both default off).
final aiCloudProvider = StateProvider<bool>((ref) => false);
final aiNotesProvider = StateProvider<bool>((ref) => false);

/// Last interstitial show time (frequency cap: 1 per 10 min).
final interstitialLastShownProvider = StateProvider<DateTime?>((ref) => null);

/// Shared ads runtime (preloaded interstitial/rewarded).
final adsServiceProvider = Provider<AdsService>((ref) => AdsService());
