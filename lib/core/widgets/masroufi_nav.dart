import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Tappable AppBar title: the home escape hatch for branches that have no
/// home destination in the bottom bar (Wallets, Mizania). Tapping the
/// brand always returns to Transactions ('/'); on home branches it is a
/// harmless no-op. Shared so all four branch pages behave identically.
class HomeTitle extends StatelessWidget {
  final String text;
  final String lang;
  const HomeTitle({super.key, required this.text, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Strings.get(lang, 'goHome'),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => context.go('/'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(text),
        ),
      ),
    );
  }
}

/// Purpose-built finance bottom bar: Wallets | dominant + | Mizania.
/// Not a generic NavigationBar: the center action is visually dominant
/// and opens the add-transaction sheet. Transactions/Dashboard are
/// switched via the top [HomeTopSwitch], so [selected] only reflects
/// the wallet/mizania branches ('wallets'|'mizania'|null for home).
class MasroufiNavBar extends StatelessWidget {
  final String? selected;
  final String lang;
  final VoidCallback onWallets;
  final VoidCallback onMizania;
  final VoidCallback onAdd;
  const MasroufiNavBar({
    super.key,
    required this.selected,
    required this.lang,
    required this.onWallets,
    required this.onMizania,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.wallet,
                label: Strings.get(lang, 'wallets'),
                active: selected == 'wallets',
                onTap: onWallets,
              ),
            ),
            // Dominant center action: 64dp filled circle, min 48dp target
            // exceeded for comfortable touch.
            Semantics(
              button: true,
              label: Strings.get(lang, 'addExpense'),
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () {
                  Haptics.tap();
                  onAdd();
                },
                child: Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: scheme.onPrimary,
                    semanticLabel: Strings.get(lang, 'addExpense'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.savings,
                label: Strings.get(lang, 'mizania'),
                active: selected == 'mizania',
                onTap: onMizania,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top switch between the two home experiences (Transactions | Dashboard).
/// Rendered at the top of both pages so the user can always cross over.
class HomeTopSwitch extends StatelessWidget {
  final bool showTransactions;
  final String lang;
  final VoidCallback onTransactions;
  final VoidCallback onDashboard;
  final VoidCallback onSettings;
  const HomeTopSwitch({
    super.key,
    required this.showTransactions,
    required this.lang,
    required this.onTransactions,
    required this.onDashboard,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(Strings.get(lang, 'viewTransactions')),
                icon: const Icon(Icons.receipt_long, size: 18),
              ),
              ButtonSegment(
                value: false,
                label: Text(Strings.get(lang, 'viewDashboard')),
                icon: const Icon(Icons.pie_chart, size: 18),
              ),
            ],
            selected: {showTransactions},
            onSelectionChanged: (s) {
              if (s.first && !showTransactions) {
                onTransactions();
              } else if (!s.first && showTransactions) {
                onDashboard();
              }
            },
          ),
        ),
        IconButton(
          tooltip: Strings.get(lang, 'settings'),
          icon: const Icon(Icons.settings),
          onPressed: onSettings,
        ),
      ],
    );
  }
}
