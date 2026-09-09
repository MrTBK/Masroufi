import 'package:drift/drift.dart';

/// Wallets. Current balance is DERIVED (initial + flows), never stored.
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('cash'))();
  IntColumn get initialMillimes => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('TND'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  // Presentation-only privacy flag: hides the displayed balance.
  // NEVER affects balance math; totals always include hidden wallets.
  BoolColumn get isBalanceHidden =>
      boolean().withDefault(const Constant(false))();
  // Visual card metadata (v6): stable keys only, resolved via WalletStyles.
  // NEVER affects balance math. Older rows default to teal/default.
  TextColumn get colorKey => text().withDefault(const Constant('teal'))();
  TextColumn get design => text().withDefault(const Constant('classic'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Categories. Defaults use [nameKey] (translated); user ones use [customName].
/// No FK from transactions: archiving/deleting never breaks history.
/// [kind] is 'expense' | 'income': income forms only offer income kinds.
/// [parentId] builds a single-level hierarchy (null = top-level parent);
/// plain-text ref, no FK (consistent with the rest of the schema).
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get nameKey => text().nullable()();
  TextColumn get customName => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('other'))();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  // Financial nature: 'important' | 'normal' | 'fun' (expense analytics).
  // Inherited by transactions from the category; never stored per txn.
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // Single-level hierarchy: id of the parent category, null = top-level.
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Transactions. Transfer = one row with [toWalletId] set; never income/expense.
/// Plain text refs (no FK constraints) so archived categories stay valid.
/// [recurringRuleId] links auto-generated occurrences (v2+); ordinary txns null.
class Transactions extends Table {
  TextColumn get id => text()();
  // expense | income | transfer
  TextColumn get type => text()();
  IntColumn get amountMillimes => integer()();
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get recurringRuleId => text().nullable()();
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

/// Recurring rules (v2). Generates ordinary transactions on due dates.
/// Plain text refs (no FK). [lastGenerated] prevents silent duplicates.
class RecurringRules extends Table {
  TextColumn get id => text()();
  // expense | income
  TextColumn get type => text()();
  IntColumn get amountMillimes => integer()();
  TextColumn get walletId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  // daily | weekly | monthly | yearly
  TextColumn get frequency => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get nextOccurrence => dateTime()();
  DateTimeColumn get lastGenerated => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Monthly per-category budgets (v2). Overall budget in [Budgets] unchanged.
class CategoryBudgets extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get amountMillimes => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Savings goals (v2). Contributions live in [SavingsContributions] — a
/// separate ledger that never touches ordinary wallet balances.
class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get targetMillimes => integer()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get walletId => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class SavingsContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  // Positive = contribution, negative = withdrawal. Int millimes.
  IntColumn get amountMillimes => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Debts (v2). [direction]: 'owe' (I owe) | 'owed' (owed to me).
/// Payments link to the real wallet transaction via [DebtPayments.txnId],
/// so balances update exactly once through the normal ledger.
class Debts extends Table {
  TextColumn get id => text()();
  TextColumn get person => text()();
  TextColumn get direction => text()();
  IntColumn get originalMillimes => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  // open | settled
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class DebtPayments extends Table {
  TextColumn get id => text()();
  TextColumn get debtId => text()();
  IntColumn get amountMillimes => integer()();
  TextColumn get walletId => text()();
  TextColumn get txnId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Transaction templates (v7). One-tap prefilled drafts for the txn form.
/// NEVER auto-create transactions: applying only prefills the form.
/// Plain-text refs, no FK (a template survives wallet/category deletion;
/// dangling refs resolve to "pick again" in the form).
class TxnTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  // expense | income | transfer
  TextColumn get type => text()();
  IntColumn get amountMillimes => integer()();
  TextColumn get walletId => text().nullable()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}
