import 'package:drift/drift.dart';

/// Wallets. Current balance is DERIVED (initial + flows), never stored.
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('cash'))();
  IntColumn get initialMillimes => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('TND'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Categories. Defaults use [nameKey] (translated); user ones use [customName].
/// No FK from transactions: archiving/deleting never breaks history.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get nameKey => text().nullable()();
  TextColumn get customName => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('other'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Transactions. Transfer = one row with [toWalletId] set; never income/expense.
/// Plain text refs (no FK constraints) so archived categories stay valid.
class Transactions extends Table {
  TextColumn get id => text()();
  // expense | income | transfer
  TextColumn get type => text()();
  IntColumn get amountMillimes => integer()();
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];
}

/// Overall monthly budget (MVP). Unique per (year, month).
class Budgets extends Table {
  TextColumn get id => text()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get amountMillimes => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value settings: language, theme, onboarding_done, user_name.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
