import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/ads/ads_service.dart';
import 'core/backup/auto_backup.dart';
import 'core/security/app_lock.dart';
import 'data/database/app_db.dart';
import 'features/lock/lock_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Locale date symbols for Arabic/French weekday + month names
  // (timeline headers, Mizania title). Never blocks startup offline.
  try {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('fr');
  } catch (_) {
    // Formatters fall back to numeric dates; app stays fully usable.
  }
  // Edge-to-edge system bars (Android polish); harmless no-op elsewhere.
  // Pages already pad with SafeArea where content meets system UI.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final db = AppDb();
  final container = ProviderContainer(
    overrides: [appDbProvider.overrideWithValue(db)],
  );
  final lang = await container.read(settingsRepoProvider).language();
  final theme = await container.read(settingsRepoProvider).theme();
  final done = await container.read(settingsRepoProvider).onboardingDone();
  final hide = await container.read(settingsRepoProvider).hideBalances();
  final weekStart = await container.read(settingsRepoProvider).weekStart();
  bool rollover = false;
  try {
    rollover = await container.read(settingsRepoProvider).rolloverEnabled();
  } catch (_) {}
  // Ads/AI/PRO flags (P2-P4, all default off, offline-cached).
  var adsConsent = false;
  var isPro = false;
  var aiCloud = false;
  var aiNotes = false;
  try {
    adsConsent = await container.read(settingsRepoProvider).adsConsent();
    isPro = await container.read(settingsRepoProvider).isPro();
    aiCloud = await container.read(settingsRepoProvider).aiCloudEnabled();
    aiNotes = await container.read(settingsRepoProvider).aiIncludeNotes();
  } catch (_) {}
  // Ads init (best-effort, never blocks startup or finance).
  // UMP consent UI is requested lazily in Settings; here we only warm up
  // MobileAds so first banner loads fast when consented.
  try {
    if (adsConsent && !isPro) {
      final ads = AdsService();
      await ads.ensureInitialized();
      await ads.preloadInterstitial();
      await ads.preloadRewarded();
    }
  } catch (_) {}
  // App lock: a stored PIN means the vault starts locked. Secure-storage
  // failures fail CLOSED only when a PIN was previously known... we cannot
  // know that without reading, so a read failure starts unlocked (same as
  // no PIN) rather than bricking the app; the settings UI shows status.
  final hasPin = await container.read(pinStoreProvider).hasPin();
  // Seed categories early so first run has Tunisian defaults.
  await container.read(categoriesRepoProvider).seedDefaults();
  // Materialize due recurring occurrences (user-controlled via active rules).
  // Safe to rerun: generation is atomic and never duplicates.
  try {
    await container.read(recurringRepoProvider).generateDue();
  } catch (_) {
    // Offline-first: a failed generation must never block startup.
  }
  // Weekly auto-backup (Track 5): filename-rotated, keep last 4.
  // Best-effort: any failure is swallowed, startup never blocks.
  try {
    final dir = await getApplicationDocumentsDirectory();
    await AutoBackup.runIfStale(db, dir);
  } catch (_) {}
  runApp(
    UncontrolledProviderScope(
      container: container
        ..read(languageProvider.notifier).state = lang
        ..read(themeNameProvider.notifier).state = theme
        ..read(onboardingDoneProvider.notifier).state = done
        ..read(hideBalancesProvider.notifier).state = hide
        ..read(weekStartProvider.notifier).state = weekStart
        ..read(rolloverProvider.notifier).state = rollover
        ..read(adsConsentProvider.notifier).state = adsConsent
        ..read(isProProvider.notifier).state = isPro
        ..read(aiCloudProvider.notifier).state = aiCloud
        ..read(aiNotesProvider.notifier).state = aiNotes
        ..read(lockEnabledProvider.notifier).state = hasPin
        ..read(lockedProvider.notifier).state = hasPin,
      child: const AppLockScope(child: MasroufiApp()),
    ),
  );
}
