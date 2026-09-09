import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';

/// 2 steps: language -> first wallet (+balance, optional name).
/// Theme stays on 'system' here (changeable later in Settings).
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int step = 0;
  String lang = 'ar';
  final walletCtl = TextEditingController();
  final balanceCtl = TextEditingController(text: '0');
  final nameCtl = TextEditingController();
  String theme = 'system';
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    lang = ref.read(languageProvider);
  }

  @override
  void dispose() {
    walletCtl.dispose();
    balanceCtl.dispose();
    nameCtl.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      int initial = 0;
      final rawBalance = balanceCtl.text.trim();
      if (rawBalance.isNotEmpty &&
          !RegExp(r'^[0\s.,]+$').hasMatch(rawBalance)) {
        initial = Money.parse(rawBalance);
      }
      final settings = ref.read(settingsRepoProvider);
      await settings.set('language', lang);
      await settings.set('theme', theme);
      final name = nameCtl.text.trim();
      if (name.isNotEmpty) await settings.set('user_name', name);
      final walletName = walletCtl.text.trim().isEmpty
          ? Strings.get(lang, 'cash')
          : walletCtl.text.trim();
      await ref
          .read(walletsRepoProvider)
          .create(name: walletName, icon: 'cash', initialMillimes: initial);
      await settings.set('onboarding_done', '1');
      ref.read(languageProvider.notifier).state = lang;
      ref.read(themeNameProvider.notifier).state = theme;
      ref.read(onboardingDoneProvider.notifier).state = true;
      if (mounted) context.go('/');
    } on FormatException {
      setState(() {
        error = Strings.get(lang, 'invalidAmount');
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'onboardingTitle'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: [_langStep(), _walletStep()][step],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (step > 0)
                TextButton(
                  onPressed: () => setState(() => step--),
                  child: Text(Strings.get(lang, 'cancel')),
                ),
              const Spacer(),
              if (step < 1)
                FilledButton(
                  onPressed: () => setState(() => step++),
                  child: Text(Strings.get(lang, 'next')),
                ),
              if (step == 1)
                FilledButton(
                  onPressed: saving ? null : finish,
                  child: Text(Strings.get(lang, 'getStarted')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        Strings.get(lang, 'onboardingLang'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.md),
      RadioGroup<String>(
        groupValue: lang,
        onChanged: (v) => setState(() => lang = v!),
        child: Column(
          children: [
            for (final l in ['ar', 'fr', 'en'])
              RadioListTile<String>(
                value: l,
                title: Text(
                  {'ar': 'العربية', 'fr': 'Français', 'en': 'English'}[l]!,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _walletStep() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          Strings.get(lang, 'onboardingWallet'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: walletCtl,
          decoration: InputDecoration(
            labelText: Strings.get(lang, 'walletName'),
            hintText: Strings.get(lang, 'cash'),
          ),
        ),
        const SizedBox(height: AppSpacing.md2),
        TextField(
          controller: balanceCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: Strings.get(lang, 'initialBalance'),
            hintText: '100',
          ),
        ),
        const SizedBox(height: AppSpacing.md2),
        TextField(
          controller: nameCtl,
          decoration: InputDecoration(
            labelText: Strings.get(lang, 'onboardingName'),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}
