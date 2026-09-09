import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/providers.dart';
import '../analytics/periods.dart';
import '../config/brand.dart';
import '../l10n/strings.dart';
import '../money/money.dart';

/// Android home-screen widget glue (brief §37).
///
/// The widget itself is native (`MasroufiWidgetProvider` + RemoteViews
/// layout): this file only pushes data. Amounts use `Money.inline`
/// (bidi isolates) because launcher TextViews apply default bidi and
/// would otherwise detach the minus sign in Arabic — same bug class as
/// §8, fixed the same way. All platform calls try/caught: a missing or
/// denied widget host must never affect the app.
final masroufiWidgetProvider = Provider<MasroufiWidget>((ref) => MasroufiWidget());

/// Pure widget text builder (unit-tested): brand + balance + today line.
({String title, String balance, String today}) widgetLines({
  required int totalMillimes,
  required int todaySpentMillimes,
  required String lang,
}) => (
  title: Brand.nameFor(lang),
  balance: Money.inline(totalMillimes, lang: lang),
  today:
      '${Strings.get(lang, 'today')}: '
      '${Money.inline(todaySpentMillimes, lang: lang)}',
);

/// Pure savings-variant builder (unit-tested, Track 7): top goal name +
/// current/target. Same provider pushes it alongside the balance view.
({String title, String balance}) savingsWidgetLines({
  required String goalName,
  required int currentMillimes,
  required int targetMillimes,
  required String lang,
}) => (
  title: goalName,
  balance:
      '${Money.inline(currentMillimes, lang: lang)} / '
      '${Money.inline(targetMillimes, lang: lang)}',
);

class MasroufiWidget {
  /// Push fresh numbers from live repos, then nudge the provider.
  /// Fire-and-forget: callers must not await success.
  Future<void> refreshFrom(WidgetRef ref) async {
    try {
      final total = await ref.read(walletsRepoProvider).visibleBalance();
      final now = DateTime.now();
      final today = Periods.day(now);
      final spent = await ref
          .read(analyticsRepoProvider)
          .expenseTotal(today.start, today.end);
      final lang = ref.read(languageProvider);
      final lines = widgetLines(
        totalMillimes: total,
        todaySpentMillimes: spent,
        lang: lang,
      );
      await HomeWidget.saveWidgetData<String>('title', lines.title);
      await HomeWidget.saveWidgetData<String>('balance', lines.balance);
      await HomeWidget.saveWidgetData<String>('today', lines.today);
      // Savings variant (same provider): push the top goal too. The
      // native provider renders the same layout for both picker entries;
      // the savings entry documents the goal without a second codebase.
      try {
        final goals = await ref.read(savingsRepoProvider).all(
          includeArchived: false,
        );
        if (goals.isNotEmpty) {
          final top = goals.first;
          final cur = await ref
              .read(savingsRepoProvider)
              .currentAmount(top.id);
          final sLines = savingsWidgetLines(
            goalName: top.name,
            currentMillimes: cur,
            targetMillimes: top.targetMillimes,
            lang: lang,
          );
          await HomeWidget.saveWidgetData<String>(
            'savings_title',
            sLines.title,
          );
          await HomeWidget.saveWidgetData<String>(
            'savings_balance',
            sLines.balance,
          );
        }
      } catch (_) {}
      await HomeWidget.updateWidget(
        androidName: 'MasroufiWidgetProvider',
        qualifiedAndroidName: 'com.masroufi.app.MasroufiWidgetProvider',
      );
    } catch (_) {}
  }
}
