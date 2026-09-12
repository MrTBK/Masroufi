import 'package:uuid/uuid.dart';

import '../database/app_db.dart';

/// Keys: language (en/fr/ar), theme (system/light/dark),
/// onboarding_done (0/1), user_name, hide_balances (0/1),
/// week_start (monday|sunday|saturday, default monday),
/// last_backup_at (ISO-8601 UTC of last successful backup, else absent).
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

  Future<void> remove(String key) =>
      (db.delete(db.appSettings)..where((s) => s.key.equals(key))).go();

  Future<String> language() async => await get('language') ?? 'en';
  Future<String> theme() async => await get('theme') ?? 'system';
  Future<bool> onboardingDone() async => await get('onboarding_done') == '1';

  /// Global privacy switch: when true every balance renders masked.
  /// Display-only; financial math never reads this flag.
  Future<bool> hideBalances() async => await get('hide_balances') == '1';
  Future<void> setHideBalances(bool hide) =>
      set('hide_balances', hide ? '1' : '0');

  /// First day of the week for analytics periods. Defaults to Monday.
  static const weekStarts = ['monday', 'sunday', 'saturday'];
  Future<String> weekStart() async {
    final v = await get('week_start');
    return weekStarts.contains(v) ? v! : 'monday';
  }

  Future<void> setWeekStart(String v) async {
    if (!weekStarts.contains(v)) throw ArgumentError('bad week_start');
    await set('week_start', v);
  }

  /// ISO-8601 timestamp of the last successful backup (UTC), or null
  /// when no backup was ever created on this install. Display-only.
  Future<DateTime?> lastBackupAt() async {
    final v = await get('last_backup_at');
    if (v == null) return null;
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastBackupAt(DateTime when) =>
      set('last_backup_at', when.toUtc().toIso8601String());

  /// Biometric unlock allowed (requires a PIN to exist; enforced by UI).
  Future<bool> bioEnabled() async => await get('bio_enabled') == '1';
  Future<void> setBioEnabled(bool v) =>
      set('bio_enabled', v ? '1' : '0');

  /// Local alert notifications (brief §33). Off by default; enabling
  /// requests the Android 13+ runtime permission first.
  Future<bool> notifEnabled() async => await get('notif_enabled') == '1';
  Future<void> setNotifEnabled(bool v) =>
      set('notif_enabled', v ? '1' : '0');

  /// Auto-lock delay after backgrounding, in seconds (0/60/300).
  static const lockTimeouts = [0, 60, 300];
  Future<int> lockTimeout() async {
    final v = int.tryParse(await get('lock_timeout') ?? '');
    return lockTimeouts.contains(v) ? v! : 60;
  }

  Future<void> setLockTimeout(int seconds) async {
    if (!lockTimeouts.contains(seconds)) {
      throw ArgumentError('bad lock_timeout');
    }
    await set('lock_timeout', '$seconds');
  }

  /// Rollover opt-in (Track 6, display-level only): when true, unused
  /// previous-month budget adds to the current budget display. Ledger
  /// untouched; defaults off.
  Future<bool> rolloverEnabled() async =>
      await get('rollover_enabled') == '1';
  Future<void> setRolloverEnabled(bool v) =>
      set('rollover_enabled', v ? '1' : '0');

  // ---- Ads + AI + PRO (P2-P4, all opt-in, offline-safe) ----
  /// Personalized-ads consent (UMP). Off by default; enabling loads
  /// AdMob banners/interstitials. Core finance never reads this.
  Future<bool> adsConsent() async => await get('ads_consent') == '1';
  Future<void> setAdsConsent(bool v) =>
      set('ads_consent', v ? '1' : '0');

  /// PRO remove-ads entitlement (Play Billing + manual code). Cached
  /// offline; verified at purchase/restore time.
  Future<bool> isPro() async => await get('is_pro') == '1';
  Future<void> setPro(bool v) => set('is_pro', v ? '1' : '0');

  /// Stable per-install id. Generated once, backs single-device PRO
  /// manual codes: a code minted for this id verifies nowhere else.
  Future<String> installId() async {
    var id = await get('install_id');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await set('install_id', id);
    }
    return id;
  }

  /// Cloud-AI opt-in (P4). Off by default; when on, redacted BI summaries
  /// may leave the device via the proxy. Notes excluded unless allowed.
  Future<bool> aiCloudEnabled() async =>
      await get('ai_cloud_enabled') == '1';
  Future<void> setAiCloudEnabled(bool v) =>
      set('ai_cloud_enabled', v ? '1' : '0');
  Future<bool> aiIncludeNotes() async =>
      await get('ai_include_notes') == '1';
  Future<void> setAiIncludeNotes(bool v) =>
      set('ai_include_notes', v ? '1' : '0');
}
