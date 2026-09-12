import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/forecast_v2.dart';
import 'package:masroufi/core/analytics/kpi.dart';

void main() {
  group('Kpi', () {
    test('net cash flow may go negative', () {
      expect(
        Kpi.netCashFlow(incomeMillimes: 100000, expenseMillimes: 150000),
        -50000,
      );
    });

    test('savings rate null on zero income, negative on overspend', () {
      expect(
        Kpi.savingsRate(incomeMillimes: 0, expenseMillimes: 100),
        isNull,
      );
      expect(
        Kpi.savingsRate(incomeMillimes: 1000000, expenseMillimes: 680000),
        32,
      );
      expect(
        Kpi.savingsRate(incomeMillimes: 100000, expenseMillimes: 150000),
        -50,
      );
    });

    test('expense growth null on zero previous', () {
      expect(
        Kpi.expenseGrowth(current: 100, previous: 0),
        isNull,
      );
      expect(
        Kpi.expenseGrowth(current: 118000, previous: 100000),
        (diff: 18000, pct: 18),
      );
    });

    test('budget utilization null without budget, over 100 when over', () {
      expect(
        Kpi.budgetUtilization(spentMillimes: 100, budgetMillimes: null),
        isNull,
      );
      expect(
        Kpi.budgetUtilization(spentMillimes: 820000, budgetMillimes: 1000000),
        82,
      );
      expect(
        Kpi.budgetUtilization(spentMillimes: 1030000, budgetMillimes: 1000000),
        103,
      );
    });

    test('health score is weighted, banded, and transparent', () {
      final h = Kpi.healthScore(
        savingsRatePct: 30,
        budgetUtilizationPct: 82,
        expenseGrowthPct: 5,
        obligationsSharePct: 10,
      );
      // savings 80*35 + adherence 64*30 + growth 70*20 + oblig 100*15
      // = 2800+1920+1400+1500 = 7620 -> 76, strong.
      expect(h.score, 76);
      expect(h.band, 'strong');
      expect(h.missing, isEmpty);
      expect(h.inputs.map((e) => e.weight), [35, 30, 20, 15]);
    });

    test('health score flags missing inputs as neutral', () {
      final h = Kpi.healthScore();
      expect(h.score, 50);
      expect(h.band, 'steady');
      expect(h.missing, hasLength(4));
      final strained = Kpi.healthScore(
        savingsRatePct: -40,
        budgetUtilizationPct: 160,
        expenseGrowthPct: 60,
        obligationsSharePct: 80,
      );
      expect(strained.band, 'strained');
    });

    test('forecast projects run-rate with overrun and pace', () {
      // Sept (30 days), day 15, 600 spent of 1000 budget.
      final f = ForecastV2.project(
        spentSoFarMillimes: 600000,
        now: DateTime(2026, 9, 15),
        budgetMillimes: 1000000,
      )!;
      expect(f.projected, 1200000);
      expect(f.overrun, 200000);
      expect(f.pacePct, 120);
    });

    test('forecast null without spend; pace 100 without budget', () {
      expect(
        ForecastV2.project(
          spentSoFarMillimes: 0,
          now: DateTime(2026, 9, 15),
          budgetMillimes: 1000000,
        ),
        isNull,
      );
      final f = ForecastV2.project(
        spentSoFarMillimes: 300000,
        now: DateTime(2026, 2, 14),
        budgetMillimes: null,
      )!;
      // Feb 2026: 28 days, daily 21429 (half-up 300000/14) -> 600012.
      expect(f.projected, 21429 * 28);
      expect(f.overrun, isNull);
      expect(f.pacePct, 100);
    });
  });
}
