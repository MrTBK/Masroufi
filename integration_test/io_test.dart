import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/budgets_repo.dart';
import 'package:masroufi/data/repositories/categories_repo.dart';
import 'package:masroufi/data/repositories/settings_repo.dart';
import 'package:masroufi/data/repositories/transactions_repo.dart';
import 'package:masroufi/data/repositories/wallets_repo.dart';
import 'package:masroufi/features/backup/backup_codec.dart';
import 'package:path_provider/path_provider.dart';

class _R {
  final WalletsRepo wallets;
  final CategoriesRepo cats;
  final TransactionsRepo txns;
  final BudgetsRepo budgets;
  final SettingsRepo settings;
  _R(AppDb db)
    : wallets = WalletsRepo(db),
      cats = CategoriesRepo(db),
      txns = TransactionsRepo(db),
      budgets = BudgetsRepo(db),
      settings = SettingsRepo(db);
}

/// On-device file I/O + end-state seeding (Track A QA 8/11/12 support).
/// Writes the QA end-state through real repos, round-trips backup JSON and
/// CSV through app storage, and leaves the app in Arabic + dark theme so a
/// plain `adb` launch + screenshot shows the localized dark dashboard.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed QA state + backup/CSV round-trip on device', (_) async {
    final db = AppDb();
    final w = _R(db);
    await w.cats.seedDefaults();

    await db.delete(db.transactions).go();
    await db.delete(db.budgets).go();
    await db.delete(db.wallets).go();
    await db.delete(db.appSettings).go();

    final cash = await w.wallets.create(name: 'Cash', initialMillimes: 100000);
    final bank = await w.wallets.create(name: 'Bank', initialMillimes: 0);
    final cats = await w.cats.all(includeArchived: false);
    final cafe = cats.firstWhere((c) => c.nameKey == 'cat_cafe').id;
    final taxi = cats.firstWhere((c) => c.nameKey == 'cat_taxi').id;

    await w.txns.addExpense(
      amountMillimes: 12500,
      walletId: cash,
      categoryId: cafe,
    );
    await w.txns.addExpense(
      amountMillimes: 8000,
      walletId: cash,
      categoryId: taxi,
    );
    await w.txns.addIncome(amountMillimes: 500000, walletId: cash);
    await w.txns.addTransfer(
      amountMillimes: 100000,
      fromWalletId: cash,
      toWalletId: bank,
    );
    final now = DateTime.now();
    await w.budgets.upsert(now.year, now.month, 250000);

    final cashRow = await w.wallets.get(cash);
    expect(await w.wallets.balance(cashRow!), 479500);
    final bankRow = await w.wallets.get(bank);
    expect(await w.wallets.balance(bankRow!), 100000);

    // Backup JSON round-trip through real app storage.
    final dir = await getApplicationDocumentsDirectory();
    final backup = BackupCodec.build({
      'wallets': [
        for (final x in await db.select(db.wallets).get())
          {'id': x.id, 'name': x.name},
      ],
      'categories': [
        for (final x in await db.select(db.categories).get()) {'id': x.id},
      ],
      'transactions': [
        for (final x in await db.select(db.transactions).get())
          {'id': x.id, 'amountMillimes': x.amountMillimes},
      ],
      'budgets': [
        for (final x in await db.select(db.budgets).get()) {'id': x.id},
      ],
      'settings': [
        {'key': 'language', 'value': 'ar'},
      ],
    });
    final bf = File('${dir.path}/qa_backup.json');
    await bf.writeAsString(BackupCodec.encode(backup));
    expect(BackupCodec.tryDecode(await bf.readAsString()), isNotNull);

    // CSV with Arabic content round-trip.
    final csv = BackupCodec.buildCsv([
      {
        'date': '2026-09-06',
        'type': 'expense',
        'amount_millimes': 12500,
        'amount_tnd': '12.500',
        'category': 'مقهى',
        'wallet': 'Cash',
        'to_wallet': '',
        'note': 'قهوة',
      },
    ]);
    final cf = File('${dir.path}/qa_export.csv');
    await cf.writeAsString('\uFEFF$csv');
    final back = await cf.readAsString();
    expect(back, contains('مقهى'));
    expect(back, contains('12500'));

    // Leave app in Arabic + dark for screenshot evidence.
    await w.settings.set('language', 'ar');
    await w.settings.set('theme', 'dark');
    await w.settings.set('onboarding_done', '1');
    await db.close();
  });
}
