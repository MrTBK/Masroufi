import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/database/app_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb();
  final container = ProviderContainer(
    overrides: [appDbProvider.overrideWithValue(db)],
  );
  final lang = await container.read(settingsRepoProvider).language();
  final theme = await container.read(settingsRepoProvider).theme();
  final done = await container.read(settingsRepoProvider).onboardingDone();
  // Seed categories early so first run has Tunisian defaults.
  await container.read(categoriesRepoProvider).seedDefaults();
  runApp(
    UncontrolledProviderScope(
      container: container
        ..read(languageProvider.notifier).state = lang
        ..read(themeNameProvider.notifier).state = theme
        ..read(onboardingDoneProvider.notifier).state = done,
      child: const MasroufiApp(),
    ),
  );
}
