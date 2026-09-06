import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_db.dart';
import '../data/repositories/budgets_repo.dart';
import '../data/repositories/categories_repo.dart';
import '../data/repositories/settings_repo.dart';
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
final budgetsRepoProvider = Provider<BudgetsRepo>(
  (ref) => BudgetsRepo(ref.watch(appDbProvider)),
);
final settingsRepoProvider = Provider<SettingsRepo>(
  (ref) => SettingsRepo(ref.watch(appDbProvider)),
);

/// UI state (persisted to app_settings on change by settings page/onboarding).
final languageProvider = StateProvider<String>((ref) => 'en');
final themeNameProvider = StateProvider<String>((ref) => 'system');
final onboardingDoneProvider = StateProvider<bool>((ref) => false);

/// Bumped to refresh dashboard aggregates after mutations.
final refreshTickProvider = StateProvider<int>((ref) => 0);
void bumpRefresh(WidgetRef ref) =>
    ref.read(refreshTickProvider.notifier).state++;
