import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// v1 -> v7 migration via the REAL automatic path: a v1-shaped file with
/// user_version=1 is opened by AppDb, whose beforeOpen must upgrade it.
/// Proves all user data survives.
void main() {
  test('v1 file upgrades to v7 with data intact', () async {
    final dir = await Directory.systemTemp.createTemp('masroufi_mig');
    final file = File('${dir.path}/v1.sqlite');
    final v1 = raw.sqlite3.open(file.path);
    v1.execute('''
      CREATE TABLE wallets (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'cash', initial_millimes INTEGER NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'TND', is_archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE categories (id TEXT NOT NULL PRIMARY KEY, name_key TEXT,
        custom_name TEXT, icon TEXT NOT NULL DEFAULT 'other',
        is_archived INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE transactions (id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL,
        amount_millimes INTEGER NOT NULL, wallet_id TEXT NOT NULL,
        to_wallet_id TEXT, category_id TEXT, occurred_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE budgets (id TEXT NOT NULL PRIMARY KEY, year INTEGER NOT NULL,
        month INTEGER NOT NULL, amount_millimes INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE app_settings ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
    ''');
    v1.execute(
      "INSERT INTO wallets VALUES ('w1','Cash','cash',100000,'TND',0,0,0)",
    );
    v1.execute(
      "INSERT INTO categories VALUES ('c1','cat_cafe',NULL,'coffee',0,0,0)",
    );
    v1.execute(
      "INSERT INTO categories VALUES ('c2','cat_groceries',NULL,'shopping_cart',0,1,0)",
    );
    v1.execute(
      "INSERT INTO categories VALUES ('c3',NULL,'My Hobby','other',0,2,0)",
    );
    v1.execute(
      "INSERT INTO transactions VALUES ('t1','expense',12500,'w1',NULL,'c1',1725600000,'',0,0)",
    );
    v1.execute("INSERT INTO budgets VALUES ('b1',2026,9,250000,0,0)");
    v1.execute("INSERT INTO app_settings VALUES ('language','ar')");
    v1.execute('PRAGMA user_version = 1');
    v1.close();

    final db = AppDb.forTesting(NativeDatabase(file));
    // First use triggers beforeOpen -> onUpgrade(1 -> 7) + backfills.
    final wallets = await db.select(db.wallets).get();
    expect(wallets.single.name, 'Cash');
    expect(wallets.single.initialMillimes, 100000);
    // v3 columns default to visible balances / expense kinds.
    expect(wallets.single.isBalanceHidden, isFalse);
    // v6 card styling defaults to teal/classic.
    expect(wallets.single.colorKey, 'teal');
    expect(wallets.single.design, 'classic');
    final cats = await db.select(db.categories).get();
    expect(cats.singleWhere((c) => c.id == 'c1').kind, 'expense');
    // v4 backfill: per-key defaults; customs stay normal.
    final byId = {for (final c in cats) c.id: c};
    expect(byId['c1']!.priority, 'normal');
    expect(byId['c2']!.priority, 'important');
    expect(byId['c3']!.priority, 'normal');
    // v5: legacy rows stay top-level (backfill only fills known children,
    // and no parents exist in this v1-shaped file).
    expect(byId['c1']!.parentId, isNull);
    expect(byId['c2']!.parentId, isNull);
    expect(byId['c3']!.parentId, isNull);
    final txns = await db.select(db.transactions).get();
    expect(txns.single.amountMillimes, 12500);
    expect(txns.single.recurringRuleId, isNull);
    final settings = await (db.select(db.appSettings)).getSingle();
    expect(settings.value, 'ar');
    // New tables usable.
    await db
        .into(db.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            id: 'r1',
            type: 'expense',
            amountMillimes: 1000,
            walletId: 'w1',
            frequency: 'monthly',
            startDate: DateTime(2026, 9, 1),
            nextOccurrence: DateTime(2026, 10, 1),
          ),
        );
    expect(await db.select(db.recurringRules).get(), hasLength(1));
    // v7 templates table exists and starts empty for upgraded users.
    expect(await db.select(db.txnTemplates).get(), isEmpty);
    await db
        .into(db.txnTemplates)
        .insert(
          TxnTemplatesCompanion.insert(
            id: 'tpl1',
            name: 'Morning coffee',
            type: 'expense',
            amountMillimes: 5500,
          ),
        );
    final templates = await db.select(db.txnTemplates).get();
    expect(templates.single.name, 'Morning coffee');
    await db.close();
    await dir.delete(recursive: true);
  });
}
