import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:masroufi/core/config/brand.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/notify/notifier.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repo.dart';
import '../lock/lock_page.dart';

/// Settings hub (spec §19): logically grouped, not one long list.
/// GENERAL / CATEGORIES / WALLETS / BUDGET / DATA / SECURITY / ABOUT.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final nameCtl = TextEditingController();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    nameCtl.text = await ref.read(settingsRepoProvider).get('user_name') ?? '';
    if (mounted) setState(() => loaded = true);
  }

  @override
  void dispose() {
    nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final theme = ref.watch(themeNameProvider);
    final hideAll = ref.watch(hideBalancesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'settings'))),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _group(context, lang, 'general'),
                _langSection(lang),
                _themeSection(lang, theme),
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'yourName'),
                  ),
                  onSubmitted: (v) =>
                      ref.read(settingsRepoProvider).set('user_name', v.trim()),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Money: where funds live and how they are controlled.
                _group(context, lang, 'money'),
                _tile(
                  context,
                  lang,
                  icon: Icons.savings,
                  title: Strings.get(lang, 'mizania'),
                  route: '/mizania',
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.wallet,
                  title: Strings.get(lang, 'manageWallets'),
                  route: '/wallets',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Strings.get(lang, 'showBalances')),
                  subtitle: Text(Strings.get(lang, 'hiddenNote')),
                  value: !hideAll,
                  onChanged: (v) async {
                    await ref.read(settingsRepoProvider).setHideBalances(!v);
                    ref.read(hideBalancesProvider.notifier).state = !v;
                  },
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.category,
                  title: Strings.get(lang, 'manageCategories'),
                  route: '/settings/categories',
                ),
                const SizedBox(height: AppSpacing.lg),
                // Analysis: understand spending.
                _group(context, lang, 'analysis'),
                _tile(
                  context,
                  lang,
                  icon: Icons.bar_chart,
                  title: Strings.get(lang, 'reports'),
                  route: '/settings/reports',
                ),
                _weekStartSection(lang),
                const SizedBox(height: AppSpacing.lg),
                // Planning: future money.
                _group(context, lang, 'planning'),
                _tile(
                  context,
                  lang,
                  icon: Icons.repeat,
                  title: Strings.get(lang, 'recurring'),
                  route: '/settings/recurring',
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.savings,
                  title: Strings.get(lang, 'savingsGoals'),
                  route: '/settings/savings',
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.handshake,
                  title: Strings.get(lang, 'debts'),
                  route: '/settings/debts',
                ),
                const SizedBox(height: AppSpacing.lg),
                _group(context, lang, 'data'),
                _tile(
                  context,
                  lang,
                  icon: Icons.backup,
                  title: Strings.get(lang, 'backup'),
                  route: '/settings/backup',
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.health_and_safety,
                  title: Strings.get(lang, 'dataHealth'),
                  route: '/settings/data-health',
                ),
                _tile(
                  context,
                  lang,
                  icon: Icons.currency_exchange,
                  title: Strings.get(lang, 'fxRate'),
                  route: '/settings/fx-rates',
                ),
                const SizedBox(height: AppSpacing.lg),
                _group(context, lang, 'notifications'),
                FutureBuilder(
                  future: ref.watch(settingsRepoProvider).notifEnabled(),
                  builder: (context, snap) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.notifications),
                    title: Text(Strings.get(lang, 'notifications')),
                    // Track 3: exact alarms + boot restore stay OFF by
                    // design (inexact digest only, best-effort). Documented
                    // in the planner; no permission dance unless enabled.
                    subtitle: Text(Strings.get(lang, 'exactAlarmNote')),
                    value: snap.data ?? false,
                    onChanged: (v) async {
                      if (v) {
                        final granted = await ref
                            .read(notifierProvider)
                            .requestPermission();
                        if (!granted) return;
                        await ref
                            .read(settingsRepoProvider)
                            .setNotifEnabled(true);
                        await ref.read(notifierProvider).replan(ref);
                      } else {
                        await ref
                            .read(settingsRepoProvider)
                            .setNotifEnabled(false);
                        await ref.read(notifierProvider).cancelAll();
                      }
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _group(context, lang, 'security'),
                _lockSection(lang),
                const SizedBox(height: AppSpacing.lg),
                _group(context, lang, 'about'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info),
                  title: Text(Strings.get(lang, 'aboutMasroufi')),
                  subtitle: Text(
                    '${Strings.get(lang, 'appVersion')}: 1.1.0+2 • ${Brand.applicationId}',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip),
                  title: Text(Strings.get(lang, 'privacyPolicy')),
                  subtitle: const Text('PRIVACY.md'),
                ),
              ],
            ),
    );
  }

  /// Real app-lock controls (replaces the old placeholder): PIN
  /// set/change/remove, biometric toggle (hardware-gated), auto-lock
  /// delay. Secrets never touch this page (see `PinStore`).
  Widget _lockSection(String lang) {
    final enabled = ref.watch(lockEnabledProvider);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(enabled ? Icons.lock : Icons.lock_open),
          title: Text(Strings.get(lang, 'appLock')),
          subtitle: enabled ? null : Text(Strings.get(lang, 'setPin')),
        ),
        if (!enabled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () =>
                  showPinSetup(context: context, ref: ref, verifyOld: false),
              child: Text(Strings.get(lang, 'setPin')),
            ),
          )
        else ...[
          FutureBuilder(
            future: Future.wait([
              ref.watch(settingsRepoProvider).bioEnabled(),
              ref.watch(bioAuthProvider).canCheck,
              ref.watch(settingsRepoProvider).lockTimeout(),
            ]),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final bioOn = snap.data![0] as bool;
              final bioCan = snap.data![1] as bool;
              final timeout = snap.data![2] as int;
              String timeoutLabel(int v) => Strings.get(
                lang,
                v == 0
                    ? 'lockImmediate'
                    : v == 60
                    ? 'lock1min'
                    : 'lock5min',
              );
              return Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Strings.get(lang, 'useBiometrics')),
                    value: bioOn && bioCan,
                    onChanged: !bioCan
                        ? null
                        : (v) async {
                            if (v) {
                              // Prove presence before enabling.
                              final ok = await ref
                                  .read(bioAuthProvider)
                                  .authenticate(Strings.get(lang, 'unlockApp'));
                              if (!ok) return;
                            }
                            await ref
                                .read(settingsRepoProvider)
                                .setBioEnabled(v);
                            setState(() {});
                          },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: timeout,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'lockTimeout'),
                    ),
                    items: [
                      for (final t in SettingsRepo.lockTimeouts)
                        DropdownMenuItem(
                          value: t,
                          child: Text(timeoutLabel(t)),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await ref.read(settingsRepoProvider).setLockTimeout(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => showPinSetup(
                            context: context,
                            ref: ref,
                            verifyOld: true,
                          ),
                          child: Text(Strings.get(lang, 'changePin')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final ok = await showPinVerify(
                              context: context,
                              ref: ref,
                            );
                            if (!ok || !mounted) return;
                            await ref.read(pinStoreProvider).clear();
                            await ref
                                .read(settingsRepoProvider)
                                .setBioEnabled(false);
                            ref.read(lockEnabledProvider.notifier).state =
                                false;
                            ref.read(lockedProvider.notifier).state = false;
                          },
                          child: Text(Strings.get(lang, 'removePin')),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _group(BuildContext context, String lang, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        Strings.get(lang, key),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String lang, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      // Chevron mirrors in RTL; never a fixed-direction glyph.
      trailing: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
      ),
      onTap: () => context.push(route),
    );
  }

  Widget _langSection(String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Strings.get(lang, 'language'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        RadioGroup<String>(
          groupValue: lang,
          onChanged: (v) async {
            await ref.read(settingsRepoProvider).set('language', v!);
            ref.read(languageProvider.notifier).state = v;
          },
          child: Column(
            children: [
              for (final l in ['ar', 'fr', 'en'])
                RadioListTile<String>(
                  value: l,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    {'ar': 'العربية', 'fr': 'Français', 'en': 'English'}[l]!,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _themeSection(String lang, String theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Strings.get(lang, 'theme'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        RadioGroup<String>(
          groupValue: theme,
          onChanged: (v) async {
            await ref.read(settingsRepoProvider).set('theme', v!);
            ref.read(themeNameProvider.notifier).state = v;
          },
          child: Column(
            children: [
              for (final t in ['system', 'light', 'dark'])
                RadioListTile<String>(
                  value: t,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Strings.get(
                      lang,
                      t == 'system'
                          ? 'themeSystem'
                          : 'theme${t[0].toUpperCase()}${t.substring(1)}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _weekStartSection(String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Strings.get(lang, 'weekStart'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        RadioGroup<String>(
          groupValue: ref.watch(weekStartProvider),
          onChanged: (v) async {
            if (v == null) return;
            await ref.read(settingsRepoProvider).setWeekStart(v);
            ref.read(weekStartProvider.notifier).state = v;
            bumpRefresh(ref);
          },
          child: Column(
            children: [
              for (final d in SettingsRepo.weekStarts)
                RadioListTile<String>(
                  value: d,
                  contentPadding: EdgeInsets.zero,
                  title: Text(Strings.get(lang, d)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
