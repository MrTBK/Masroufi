import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/fx/fx.dart';
import '../../core/l10n/strings.dart';
import '../../core/widgets/widgets.dart';

/// Manual offline FX rates (Track 8, no schema, KV only).
/// Rate = TND millimes per 1 foreign major unit (e.g. 3400 = 3.400 TND
/// per 1 EUR). Display-only conversion; ledger stays TND millimes.
/// Timestamp tracks staleness (>30 days → badge).
class FxRatesPage extends ConsumerStatefulWidget {
  const FxRatesPage({super.key});
  @override
  ConsumerState<FxRatesPage> createState() => _FxRatesPageState();
}

class _FxRatesPageState extends ConsumerState<FxRatesPage> {
  final ctls = {for (final c in Fx.supported) c: TextEditingController()};
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepoProvider);
    for (final c in Fx.supported) {
      ctls[c]!.text = await repo.get(Fx.rateKey(c)) ?? '';
    }
    if (mounted) setState(() => loaded = true);
  }

  @override
  void dispose() {
    for (final c in ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    if (!loaded) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'fxRate'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final c in Fx.supported)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: ctls[c],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '$c → TND (${Strings.get(lang, 'fxRate')})',
                  hintText: 'e.g. 3400',
                ),
                onSubmitted: (v) async {
                  final rate = int.tryParse(v.trim());
                  if (rate == null || rate <= 0) return;
                  final repo = ref.read(settingsRepoProvider);
                  await repo.set(Fx.rateKey(c), '$rate');
                  await repo.set(
                    Fx.rateAtKey(c),
                    DateTime.now().toUtc().toIso8601String(),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Strings.get(lang, 'saved'))),
                  );
                },
              ),
            ),
          Text(
            Strings.get(lang, 'staleRate'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
