import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/brand.dart';
import '../core/notify/notifier.dart';
import '../core/routing/router.dart';
import '../core/widget/masroufi_widget.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';

class MasroufiApp extends ConsumerWidget {
  const MasroufiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final themeName = ref.watch(themeNameProvider);
    final router = ref.watch(routerProvider);
    // Rebuild the local alert plan + home widget once per launch
    // (covers reboots; WidgetRef is only available here, not in main()).
    if (!ref.watch(notifBootstrappedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (ref.read(notifBootstrappedProvider)) return;
        ref.read(notifBootstrappedProvider.notifier).state = true;
        await ref.read(notifierProvider).replan(ref);
        await ref.read(masroufiWidgetProvider).refreshFrom(ref);
      });
    }
    return MaterialApp.router(
      title: Brand.nameFor(lang),
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: switch (themeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
