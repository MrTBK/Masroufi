import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/analytics/anomaly.dart';
import 'package:masroufi/core/analytics/forecast_v2.dart';
import 'package:masroufi/core/analytics/seasonality.dart';
import 'package:masroufi/core/analytics/whatif.dart';

void main() {
  group('Seasonality', () {
    test('shiftYearsBack moves range 1y', () {
      final s = Seasonality.shiftYearsBack(
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      expect(s.start, DateTime(2025, 9, 1));
      expect(s.end, DateTime(2025, 10, 1));
    });

    test('yoyForRange null when prior is 0', () {
      expect(Seasonality.yoyForRange(current: 100, priorYear: 0), isNull);
      expect(Seasonality.yoyForRange(current: 150, priorYear: 100), (
        diff: 50,
        pct: 50,
      ));
    });

    test('seasonalAverage ignores zeros, null when empty', () {
      expect(Seasonality.seasonalAverage([]), isNull);
      expect(Seasonality.seasonalAverage([0, 0]), isNull);
      expect(Seasonality.seasonalAverage([100, 200, 300]), 200);
    });

    test('band needs 2+ months', () {
      expect(Seasonality.band([100]), isNull);
      expect(Seasonality.band([100, 300]), isNotNull);
    });
  });

  group('ForecastV2', () {
    test('run-rate + recurring + band', () {
      final f = ForecastV2.project(
        spentSoFarMillimes: 150000,
        now: DateTime(2026, 9, 15),
        budgetMillimes: 500000,
        remainingRecurringMillimes: 50000,
        avg3mMillimes: 400000,
      )!;
      // run-rate 150k/15*30 = 300k + 50k recurring = 350k.
      expect(f.projected, 350000);
      expect(f.low, lessThan(f.high));
      expect(f.pacePct, 70);
      expect(f.overrun, -150000);
    });

    test('null when nothing spent and no recurring', () {
      expect(
        ForecastV2.project(
          spentSoFarMillimes: 0,
          now: DateTime(2026, 9, 15),
          budgetMillimes: 500000,
        ),
        isNull,
      );
    });

    test('prorateRemaining halves mid-month', () {
      // September has 30 days; on Sep 16, 15 days remain → ~50%.
      final v = ForecastV2.prorateRemaining(
        monthlyEstimateMillimes: 30000,
        now: DateTime(2026, 9, 16),
      );
      expect(v, 15000);
    });
  });

  group('Anomaly', () {
    test('flags spike over mean+2sd, ignores short history', () {
      final flags = Anomaly.detect(
        currentByCat: {'a': 100000, 'b': 6000},
        historyByCat: {
          'a': [20000, 21000, 19000, 20000],
          'b': [1000],
        },
      );
      expect(flags.map((f) => f.id), contains('a'));
      expect(flags.map((f) => f.id), isNot(contains('b')));
      expect(flags.first.pctOver, greaterThan(100));
    });

    test('no flags under floor or flat', () {
      expect(
        Anomaly.detect(
          currentByCat: {'a': 1000},
          historyByCat: {
            'a': [20000, 21000, 19000],
          },
        ),
        isEmpty,
      );
    });
  });

  group('WhatIf', () {
    test('savedByCut half-up + clamp', () {
      expect(WhatIf.savedByCut(categorySpendMillimes: 10001, cutPct: 20), 2000);
      expect(WhatIf.savedByCut(categorySpendMillimes: 10000, cutPct: 0), 0);
      expect(
        WhatIf.savedByCut(categorySpendMillimes: 10000, cutPct: 150),
        10000,
      );
    });

    test('apply sums biggest-first, projectedAfter floors', () {
      final r = WhatIf.apply(
        spendByCat: {'a': 100000, 'b': 50000},
        cuts: {'a': 20, 'b': 10},
      );
      expect(r.totalSaved, 25000);
      expect(r.lines.first.id, 'a');
      expect(
        WhatIf.projectedAfter(projectedMillimes: 300000, savedMillimes: 25000),
        275000,
      );
      expect(
        WhatIf.projectedAfter(projectedMillimes: 1000, savedMillimes: 5000),
        0,
      );
    });
  });
}
