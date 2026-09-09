import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/data/database/app_db.dart';

void main() {
  AppDb db() => AppDb.forTesting(NativeDatabase.memory());

  test('templates rename + move reorder', () async {
    final d = db();
    final repo = d.txnTemplates;
    // Use repo via provider layer to exercise real code.
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(d)],
    );
    final templates = container.read(templatesRepoProvider);
    final a = await templates.create(
      name: 'A',
      type: 'expense',
      amountMillimes: 1000,
    );
    final b = await templates.create(
      name: 'B',
      type: 'expense',
      amountMillimes: 2000,
    );
    var all = await templates.all();
    expect(all.map((t) => t.name).toList(), ['A', 'B']);

    await templates.rename(a, 'A2');
    expect((await templates.get(a))!.name, 'A2');

    // Move B up → order B, A2.
    await templates.move(b, -1);
    all = await templates.all();
    expect(all.map((t) => t.id).toList(), [b, a]);

    // Edge: moving top up is a no-op.
    await templates.move(b, -1);
    all = await templates.all();
    expect(all.first.id, b);
    expect(repo, isNotNull);
    await d.close();
    container.dispose();
  });

  test('calendar month pager provider defaults to current month', () {
    final container = ProviderContainer();
    final m = container.read(calMonthProvider);
    final now = DateTime.now();
    expect(m.year, now.year);
    expect(m.month, now.month);
    expect(m.day, 1);
    // Chevron math: prev/next month.
    DateTime prev(DateTime x) => DateTime(
      x.month == 1 ? x.year - 1 : x.year,
      x.month == 1 ? 12 : x.month - 1,
      1,
    );
    expect(prev(DateTime(2026, 1, 1)), DateTime(2025, 12, 1));
    expect(prev(DateTime(2026, 9, 1)), DateTime(2026, 8, 1));
    container.dispose();
  });

  test('track3 l10n keys exist ×3', () {
    for (final lang in ['en', 'fr', 'ar']) {
      for (final k in [
        'csvBackupFirst',
        'csvUndo',
        'csvUndone',
        'savingsSeparate',
        'exactAlarmNote',
        'calPrev',
        'calNext',
        'renameTemplate',
        'templateRenamed',
      ]) {
        expect(Strings.get(lang, k), isNot(equals(k)), reason: '$lang/$k');
      }
      // Existing move keys reused for template reorder.
      expect(Strings.get(lang, 'moveUp'), isNot(equals('moveUp')));
    }
  });
}
