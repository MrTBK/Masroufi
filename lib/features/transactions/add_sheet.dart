import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';

/// Bottom-sheet triage for the dominant + action: Expense | Income | Transfer.
/// Each row pushes the existing TxnFormPage (logic untouched).
Future<void> showAddSheet(BuildContext context, String lang) {
  return showModalBottomSheet(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _AddRow(
              icon: Icons.remove,
              label: Strings.get(lang, 'addExpense'),
              primary: true,
              onTap: () {
                Haptics.select();
                Navigator.pop(c);
                context.push('/add?type=expense');
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AddRow(
                    icon: Icons.add,
                    label: Strings.get(lang, 'addIncome'),
                    onTap: () {
                      Haptics.select();
                      Navigator.pop(c);
                      context.push('/add?type=income');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AddRow(
                    icon: Icons.swap_horiz,
                    label: Strings.get(lang, 'addTransfer'),
                    onTap: () {
                      Haptics.select();
                      Navigator.pop(c);
                      context.push('/add?type=transfer');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AddRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _AddRow({
    required this.icon,
    required this.label,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: primary ? 26 : 22),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: primary ? const TextStyle(fontSize: 18) : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: child,
          ),
        ),
      );
    }
    return OutlinedButton(onPressed: onTap, child: child);
  }
}
