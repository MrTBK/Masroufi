import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'settings'))),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
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
                          title: Text(
                            {
                              'ar': 'العربية',
                              'fr': 'Français',
                              'en': 'English',
                            }[l]!,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
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
                const Divider(),
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: Strings.get(lang, 'yourName'),
                  ),
                  onSubmitted: (v) =>
                      ref.read(settingsRepoProvider).set('user_name', v.trim()),
                ),
              ],
            ),
    );
  }
}
