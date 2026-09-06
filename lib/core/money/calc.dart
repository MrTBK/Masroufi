/// Pure financial calculations over plain data (unit-testable, no DB).
/// Amounts are int millimes. Transfers never count as income/expense.
abstract final class FinanceCalc {
  /// Wallet balance = initial + income - expense + transfersIn - transfersOut.
  static int walletBalance({
    required int initialMillimes,
    required int incomeMillimes,
    required int expenseMillimes,
    required int transfersInMillimes,
    required int transfersOutMillimes,
  }) =>
      initialMillimes +
      incomeMillimes -
      expenseMillimes +
      transfersInMillimes -
      transfersOutMillimes;

  /// A transfer preserves total money: from loses X, to gains X.
  static (int fromBalance, int toBalance) applyTransfer({
    required int fromBalance,
    required int toBalance,
    required int amountMillimes,
  }) => (fromBalance - amountMillimes, toBalance + amountMillimes);

  static int budgetRemaining({
    required int budgetMillimes,
    required int spentMillimes,
  }) => budgetMillimes - spentMillimes;

  static double budgetUsedPct({
    required int budgetMillimes,
    required int spentMillimes,
  }) {
    if (budgetMillimes <= 0) return 0;
    return spentMillimes / budgetMillimes;
  }
}
