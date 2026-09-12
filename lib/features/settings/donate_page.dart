import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';

/// Donations (Tunisia): D17 + Ba9chich, copy-to-clipboard, zero new
/// deps. No tracking, no amounts leave the device.
class DonatePage extends ConsumerWidget {
  const DonatePage({super.key});

  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    String text,
  ) async {
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      final lang = ref.read(languageProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.get(lang, 'saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'donate'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: const Icon(
                    Icons.volunteer_activism,
                    size: 28,
                    semanticLabel: 'donate',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.get(lang, 'donateTitle'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        Strings.get(lang, 'donateBody'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                for (final k in ['donateWhy1', 'donateWhy2', 'donateWhy3'])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 20,
                          color: AppColors.expense,
                          semanticLabel: Strings.get(lang, k),
                        ),
                        const SizedBox(width: AppSpacing.md2),
                        Expanded(
                          child: Text(
                            Strings.get(lang, k),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(
                    Icons.smartphone,
                    size: 22,
                    semanticLabel: 'D17',
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'D17',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          Brand.proD17Number,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: Strings.get(lang, 'proCopy'),
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, ref, Brand.proD17Number),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(
                    Icons.volunteer_activism,
                    size: 22,
                    semanticLabel: 'Ba9chich',
                  ),
                ),
                const SizedBox(width: AppSpacing.md2),
                Expanded(
                  child: Text(
                    'Ba9chich',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: Strings.get(lang, 'proCopyLink'),
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, ref, Brand.ba9chichUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
