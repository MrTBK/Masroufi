import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/providers.dart';
import '../../data/database/category_hierarchy.dart';
import '../analytics/periods.dart';
import '../l10n/strings.dart';
import 'notify_planner.dart';

/// Thin delivery layer over the pure [NotificationPlanner] (brief §33).
/// Everything platform-flavored is try/caught: notifications are
/// best-effort alerts, never load-bearing. Inexact scheduling is used
/// deliberately (no exact-alarm permission dance); the plan is rebuilt
/// on every app start and after each saved transaction, so alerts stay
/// fresh without boot receivers or background workers (documented
/// limitation: a reboot clears scheduled alerts until next launch).
final notifierProvider = Provider<AppNotifier>((ref) => AppNotifier());

/// One-shot guard so the startup replan in `MasroufiApp` runs once.
final notifBootstrappedProvider = StateProvider<bool>((ref) => false);

class AppNotifier {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _tzInit = false;

  Future<FlutterLocalNotificationsPlugin?> _ensure() async {
    if (_plugin != null) return _plugin;
    try {
      if (!_tzInit) {
        tzdata.initializeTimeZones();
        _tzInit = true;
      }
      final p = FlutterLocalNotificationsPlugin();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await p.initialize(settings: const InitializationSettings(android: android));
      await p
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'masroufi_alerts',
              'Masroufi alerts',
              importance: Importance.defaultImportance,
            ),
          );
      _plugin = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  /// Android 13+ runtime permission. Returns true when alerts may show.
  Future<bool> requestPermission() async {
    try {
      final p = await _ensure();
      final granted = await p
          ?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelAll() async {
    try {
      await (await _ensure())?.cancelAll();
    } catch (_) {}
  }

  /// Rebuild the whole alert plan from live repos and reschedule.
  /// Fire-and-forget: callers must not await success.
  Future<void> replan(WidgetRef ref) async {
    try {
      if (!await ref.read(settingsRepoProvider).notifEnabled()) return;
      final plugin = await _ensure();
      if (plugin == null) return;
      final budgets = ref.read(budgetsRepoProvider);
      final catBudgets = ref.read(categoryBudgetsRepoProvider);
      final catsRepo = ref.read(categoriesRepoProvider);
      final recurring = ref.read(recurringRepoProvider);
      final analytics = ref.read(analyticsRepoProvider);
      final lang = ref.read(languageProvider);
      final now = DateTime.now();

      BudgetInput? overall;
      final budget = await budgets.getMonth(now.year, now.month);
      if (budget != null) {
        overall = BudgetInput(
          amountMillimes: budget.amountMillimes,
          spentMillimes: await budgets.spent(now.year, now.month),
        );
      }
      final cats = await catsRepo.all();
      final byId = {for (final c in cats) c.id: c};
      final catRows = await catBudgets.forMonth(now.year, now.month);
      final catInputs = <BudgetInput>[];
      for (final cb in catRows) {
        final st = await catBudgets.status(cb.categoryId, now.year, now.month);
        final c = byId[cb.categoryId];
        catInputs.add(
          BudgetInput(
            categoryName: c == null
                ? null
                : CategoryHierarchy.displayName(lang, c, byId),
            amountMillimes: cb.amountMillimes,
            spentMillimes: st.spent,
          ),
        );
      }
      // Rules due tomorrow (by calendar day, any rule type).
      final tomorrow = Periods.dayStart(now).add(const Duration(days: 1));
      final upcoming = await recurring.upcoming(days: 2, limit: 20);
      final due = <RecurringInput>[];
      for (final u in upcoming) {
        if (Periods.dayStart(u.date) != tomorrow) continue;
        final c = u.rule.categoryId == null
            ? null
            : byId[u.rule.categoryId];
        final name = u.rule.note.isNotEmpty
            ? u.rule.note
            : c == null
            ? Strings.get(lang, u.rule.type == 'income' ? 'income' : 'expense')
            : Strings.categoryName(lang, c.nameKey, c.customName);
        due.add(RecurringInput(name: name, amountMillimes: u.rule.amountMillimes));
      }
      final today = Periods.day(now);
      final todaySpent = await analytics.expenseTotal(today.start, today.end);
      final month = Periods.month(now);
      final monthSpent = await analytics.expenseTotal(month.start, month.end);
      final elapsed = Periods.elapsedDays(month.start, month.end, now);
      final plan = NotificationPlanner.plan(
        lang: lang,
        now: now,
        overall: overall,
        categories: catInputs,
        dueTomorrow: due,
        todaySpentMillimes: todaySpent,
        dailyAverageMillimes: monthSpent ~/ elapsed,
        // Track 6: projection reuses the partialMonth run-rate.
        projectionSpent: monthSpent,
        projectionBudget: budget?.amountMillimes,
        projectionElapsed: elapsed,
        projectionDays: Periods.daysInMonth(now.year, now.month),
      );
      await plugin.cancelAll();
      for (final n in plan) {
        await plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          scheduledDate: tz.TZDateTime.from(n.when, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'masroufi_alerts',
              'Masroufi alerts',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {}
  }
}
