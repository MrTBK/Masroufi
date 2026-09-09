import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/widgets/masroufi_nav.dart';
import '../../features/backup/backup_page.dart';
import '../../features/budgets/budget_page.dart';
import '../../features/categories/categories_page.dart';
import '../../features/dashboard/category_detail_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/debts/debts_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/recurring/recurring_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/savings/savings_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/transactions/history_page.dart';
import '../../features/transactions/add_sheet.dart';
import '../../features/transactions/transactions_page.dart';
import '../../features/transactions/txn_form_page.dart';
import '../../features/wallets/wallets_page.dart';

/// Primary IA (redesign):
///
/// ```
///              MASROUFI
///                 │
///  ┌─────────────┼──────────────┐
///  │             │              │
/// WALLETS        +           MIZANIA
///  │             │              │
///  │       Add Expense       Budget
///  │       Add Income
///  │       Transfer
///  │
///  └─────────────┬──────────────┘
///                │
///          TRANSACTIONS
///                │
///       ┌────────┴────────┐
///       │                 │
///  Transactions      Dashboard
///       │                 │
///   Timeline         Analytics
/// ```
///
/// Bottom bar is purpose-built (Wallets | + | Mizania); Transactions and
/// Dashboard share the home position and switch via [HomeTopSwitch].
/// Settings lives outside the primary bar (AppBar action → /settings hub).
/// Legacy /more/* and /history routes redirect so old links/tests survive.
final routerProvider = Provider<GoRouter>((ref) {
  final done = ref.watch(onboardingDoneProvider);
  return GoRouter(
    initialLocation: done ? '/' : '/onboarding',
    redirect: (context, state) {
      final onb = state.matchedLocation == '/onboarding';
      if (!done && !onb) return '/onboarding';
      if (done && onb) return '/';
      // Legacy compat redirects.
      const legacy = {
        '/history': '/',
        '/more': '/settings',
        '/more/reports': '/settings/reports',
        '/more/budget': '/mizania',
        '/more/categories': '/settings/categories',
        '/more/backup': '/settings/backup',
        '/more/recurring': '/settings/recurring',
        '/more/savings': '/settings/savings',
        '/more/debts': '/settings/debts',
        '/more/settings': '/settings',
      };
      return legacy[state.matchedLocation];
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (c, s) => const TransactionsPage()),
              GoRoute(
                path: '/history',
                builder: (c, s) => const TransactionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (c, s) => const DashboardPage(),
              ),
              GoRoute(
                path: '/dashboard/category/:id',
                builder: (c, s) =>
                    CategoryDetailPage(categoryId: s.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/wallets', builder: (c, s) => const WalletsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/mizania', builder: (c, s) => const BudgetPage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/add',
        builder: (c, s) {
          final q = s.uri.queryParameters;
          return TxnFormPage(
            initialType: q['type'] ?? 'expense',
            editId: q['edit'],
          );
        },
      ),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
      GoRoute(
        path: '/settings/reports',
        builder: (c, s) => const ReportsPage(),
      ),
      GoRoute(
        path: '/settings/categories',
        builder: (c, s) => const CategoriesPage(),
      ),
      GoRoute(path: '/settings/backup', builder: (c, s) => const BackupPage()),
      GoRoute(
        path: '/settings/recurring',
        builder: (c, s) => const RecurringPage(),
      ),
      GoRoute(
        path: '/settings/savings',
        builder: (c, s) => const SavingsPage(),
      ),
      GoRoute(path: '/settings/debts', builder: (c, s) => const DebtsPage()),
      // Legacy history page kept importable (filters shared with the new
      // Transactions page); route itself redirects to '/'.
      GoRoute(path: '/legacy-history', builder: (c, s) => const HistoryPage()),
    ],
  );
});

/// System back on the Wallets/Mizania branches returns to Transactions
/// instead of exiting the app: branch switches never pile onto the back
/// stack, so without this the user would be trapped (no home destination
/// in the bottom bar) or dropped to the OS. Pure helper, unit-tested.
bool shouldInterceptBack(int branchIndex) =>
    branchIndex == 2 || branchIndex == 3;

class ScaffoldWithNav extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const ScaffoldWithNav({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final idx = shell.currentIndex;
    final selected = idx == 2
        ? 'wallets'
        : idx == 3
        ? 'mizania'
        : null;
    // Dialogs/sheets pushed above (add sheet, wallet dialog) are separate
    // routes: back dismisses them normally and never reaches this scope.
    return PopScope(
      canPop: !shouldInterceptBack(idx),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && shouldInterceptBack(shell.currentIndex)) {
          shell.goBranch(0);
        }
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: MasroufiNavBar(
          selected: selected,
          lang: lang,
          onWallets: () => shell.goBranch(2),
          onMizania: () => shell.goBranch(3),
          onAdd: () => showAddSheet(context, lang),
        ),
      ),
    );
  }
}

/// Settings hub entries (used by SettingsPage grouping).
/// Kept here so router + settings share one route table.
abstract final class SettingsRoutes {
  static List<({String key, IconData icon, String route, String group})>
  entries(String lang) => [
    (
      key: 'manageCategories',
      icon: Icons.category,
      route: '/settings/categories',
      group: 'categories',
    ),
    (
      key: 'manageWallets',
      icon: Icons.wallet,
      route: '/wallets',
      group: 'categories',
    ),
    (
      key: 'budget',
      icon: Icons.savings,
      route: '/mizania',
      group: 'categories',
    ),
    (
      key: 'reports',
      icon: Icons.bar_chart,
      route: '/settings/reports',
      group: 'analysis',
    ),
    (
      key: 'recurring',
      icon: Icons.repeat,
      route: '/settings/recurring',
      group: 'money',
    ),
    (
      key: 'savingsGoals',
      icon: Icons.savings,
      route: '/settings/savings',
      group: 'money',
    ),
    (
      key: 'debts',
      icon: Icons.handshake,
      route: '/settings/debts',
      group: 'money',
    ),
    (
      key: 'backup',
      icon: Icons.backup,
      route: '/settings/backup',
      group: 'data',
    ),
  ];

  static String groupLabel(String lang, String group) =>
      Strings.get(lang, switch (group) {
        'money' => 'money',
        'analysis' => 'analysis',
        'data' => 'data',
        _ => 'customization',
      });
}
