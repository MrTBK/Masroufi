import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../features/backup/backup_page.dart';
import '../../features/budgets/budget_page.dart';
import '../../features/categories/categories_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/transactions/history_page.dart';
import '../../features/transactions/txn_form_page.dart';
import '../../features/wallets/wallets_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final done = ref.watch(onboardingDoneProvider);
  return GoRouter(
    initialLocation: done ? '/' : '/onboarding',
    redirect: (context, state) {
      final onb = state.matchedLocation == '/onboarding';
      if (!done && !onb) return '/onboarding';
      if (done && onb) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/history', builder: (c, s) => const HistoryPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/wallets', builder: (c, s) => const WalletsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (c, s) => const MorePage()),
              GoRoute(
                path: '/more/reports',
                builder: (c, s) => const ReportsPage(),
              ),
              GoRoute(
                path: '/more/budget',
                builder: (c, s) => const BudgetPage(),
              ),
              GoRoute(
                path: '/more/categories',
                builder: (c, s) => const CategoriesPage(),
              ),
              GoRoute(
                path: '/more/backup',
                builder: (c, s) => const BackupPage(),
              ),
              GoRoute(
                path: '/more/settings',
                builder: (c, s) => const SettingsPage(),
              ),
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
    ],
  );
});

class ScaffoldWithNav extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const ScaffoldWithNav({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return Scaffold(
      body: shell,
      floatingActionButton: shell.currentIndex == 0
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => context.push('/add?type=expense'),
              icon: const Icon(Icons.remove),
              label: Text(Strings.get(lang, 'expense')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home),
            label: Strings.get(lang, 'dashboard'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long),
            label: Strings.get(lang, 'history'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.wallet),
            label: Strings.get(lang, 'wallets'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            label: Strings.get(lang, 'more'),
          ),
        ],
      ),
    );
  }
}

class MorePage extends ConsumerWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final items = [
      ('reports', Icons.bar_chart, '/more/reports'),
      ('budget', Icons.savings, '/more/budget'),
      ('category', Icons.category, '/more/categories'),
      ('backup', Icons.backup, '/more/backup'),
      ('settings', Icons.settings, '/more/settings'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'more'))),
      body: ListView(
        children: [
          for (final (key, icon, route) in items)
            ListTile(
              leading: Icon(icon),
              title: Text(
                key == 'category'
                    ? Strings.get(lang, 'category')
                    : Strings.get(lang, key),
              ),
              onTap: () => context.push(route),
            ),
        ],
      ),
    );
  }
}
