import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/money/calc.dart';

void main() {
  group('FinanceCalc', () {
    test('MVP wallet chain', () {
      // Cash 100.000 - 12.500 - 8.000 + 500.000 = 579.500
      final b = FinanceCalc.walletBalance(
        initialMillimes: 100000,
        incomeMillimes: 500000,
        expenseMillimes: 20500,
        transfersInMillimes: 0,
        transfersOutMillimes: 0,
      );
      expect(b, 579500);
    });

    test('transfer conserves total money', () {
      final (from, to) = FinanceCalc.applyTransfer(
        fromBalance: 579500,
        toBalance: 0,
        amountMillimes: 100000,
      );
      expect(from, 479500);
      expect(to, 100000);
      expect(from + to, 579500);
    });

    test('budget remaining + pct', () {
      expect(
        FinanceCalc.budgetRemaining(
          budgetMillimes: 250000,
          spentMillimes: 50000,
        ),
        200000,
      );
      expect(
        FinanceCalc.budgetUsedPct(budgetMillimes: 250000, spentMillimes: 50000),
        0.2,
      );
    });

    test('over-budget stays precise', () {
      expect(
        FinanceCalc.budgetRemaining(
          budgetMillimes: 250000,
          spentMillimes: 300000,
        ),
        -50000,
      );
      expect(
        FinanceCalc.budgetUsedPct(
          budgetMillimes: 250000,
          spentMillimes: 300000,
        ),
        1.2,
      );
    });
  });
}
