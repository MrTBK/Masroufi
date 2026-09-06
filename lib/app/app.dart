import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/brand.dart';
import '../core/routing/router.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';

class MasroufiApp extends ConsumerWidget {
  const MasroufiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final themeName = ref.watch(themeNameProvider);
    final router = ref.watch(routerProvider);
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
