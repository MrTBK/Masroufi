import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// PRO/donate nudge: users who never open Settings never learn PRO
/// exists. Shown on the home timeline once the install proves sticky
/// (5+ launches), then at most every 14 days, never for PRO, max once
/// per session. Bottom sheet, dismissible, no push notifications.
abstract final class Nudge {
  static bool _shownThisSession = false;

  /// Pure schedule check (unit-tested).
  static bool due({
    required int launches,
    required DateTime? lastShown,
    required DateTime now,
    required bool isPro,
  }) {
    if (isPro) return false;
    if (launches < 5) return false;
    if (lastShown == null) return true;
    return now.difference(lastShown).inDays >= 14;
  }

  /// Fire-and-forget entry for home pages. Safe to call every build.
  static void maybeShow(BuildContext context, WidgetRef ref) {
    if (_shownThisSession) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_shownThisSession) return;
      try {
        final repo = ref.read(settingsRepoProvider);
        final pro = ref.read(isProProvider);
        final launches = await repo.appLaunches();
        final last = await repo.proNudgeAt();
        if (!due(
          launches: launches,
          lastShown: last,
          now: DateTime.now(),
          isPro: pro,
        )) {
          return;
        }
        _shownThisSession = true;
        await repo.setProNudgeAt(DateTime.now());
        if (!context.mounted) return;
        final lang = ref.read(languageProvider);
        await showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(
                          c,
                        ).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(
                          c,
                        ).colorScheme.onPrimaryContainer,
                        child: const Icon(
                          Icons.workspace_premium,
                          semanticLabel: 'PRO',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md2),
                      Expanded(
                        child: Text(
                          Strings.get(lang, 'nudgeTitle'),
                          style: Theme.of(c).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(Strings.get(lang, 'nudgeBody')),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(c);
                            context.push('/settings/pro');
                          },
                          child: Text(Strings.get(lang, 'proTitle')),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(c);
                            context.push('/settings/donate');
                          },
                          child: Text(Strings.get(lang, 'donate')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (_) {}
    });
  }
}
