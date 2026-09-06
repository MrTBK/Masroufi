import '../database/app_db.dart';

/// Keys: language (en/fr/ar), theme (system/light/dark),
/// onboarding_done (0/1), user_name.
class SettingsRepo {
  final AppDb db;
  SettingsRepo(this.db);

  Future<String?> get(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(AppSetting(key: key, value: value));

  Future<String> language() async => await get('language') ?? 'en';
  Future<String> theme() async => await get('theme') ?? 'system';
  Future<bool> onboardingDone() async => await get('onboarding_done') == '1';
}
