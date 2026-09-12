import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'donate'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.get(lang, 'donateTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  Strings.get(lang, 'donateBody'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(
                        '${Strings.get(lang, 'proCopy')} ${Brand.proD17Number}',
                      ),
                      onPressed: () =>
                          _copy(context, ref, Brand.proD17Number),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(Strings.get(lang, 'proCopyLink')),
                      onPressed: () =>
                          _copy(context, ref, Brand.ba9chichUrl),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
