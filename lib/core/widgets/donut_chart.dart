import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../money/money.dart';
import '../theme/app_theme.dart';
import 'design.dart';

/// Donut / pie spending chart (CustomPainter, no chart dependency).
/// Segments from real [slices] (value > 0, sorted desc by caller).
/// Center shows the period total. Empty input renders an empty state,
/// never a broken chart. Readable in light/dark + RTL: labels are
/// outside the painter, amounts via [Money.format].
class DonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final int totalMillimes;
  final String lang;
  final double size;
  const DonutChart({
    super.key,
    required this.slices,
    required this.totalMillimes,
    required this.lang,
    this.size = 180,
  });

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty || totalMillimes <= 0) {
      return SizedBox(
        height: size,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                Strings.get(lang, 'noExpensesYet'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label:
          '${Strings.get(lang, 'totalSpent')}: '
          '${Money.inline(totalMillimes, lang: lang)}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _DonutPainter(
                slices: slices,
                total: totalMillimes.toDouble(),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(
                  millimes: totalMillimes,
                  lang: lang,
                  type: 'neutral',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  Strings.get(lang, 'totalSpent'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DonutSlice {
  final String? id;
  final String label;
  final String? iconKey;
  final int value;
  final Color color;
  DonutSlice({
    required this.id,
    required this.label,
    required this.iconKey,
    required this.value,
    required this.color,
  });
}

/// Fixed categorical palette, 8 entries cycled, resolved per brightness
/// from [AppChartColors] (single token home). Chart color carries no
/// financial meaning; type stays typographic.
abstract final class DonutPalette {
  static const List<Color> colors = AppChartColors.light;

  static List<Color> of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppChartColors.dark
      : AppChartColors.light;
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  final double total;
  _DonutPainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const thickness = 26.0;
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = total <= 0 ? 0.0 : (s.value / total) * math.pi * 2;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt;
      // Small gap between segments for readability.
      const gap = 0.02;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - thickness / 2),
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total;
}

/// Horizontal income-vs-expense bars (no chart dependency).
class MoneyInOutBars extends StatelessWidget {
  final int incomeMillimes;
  final int expenseMillimes;
  final String lang;
  const MoneyInOutBars({
    super.key,
    required this.incomeMillimes,
    required this.expenseMillimes,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(incomeMillimes, expenseMillimes).toDouble();
    double frac(int v) => maxV <= 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
    return Column(
      children: [
        _bar(
          context,
          label: Strings.get(lang, 'moneyIn'),
          value: incomeMillimes,
          fraction: frac(incomeMillimes),
          color: AppColors.income,
          glyph: '+',
        ),
        const SizedBox(height: 10),
        _bar(
          context,
          label: Strings.get(lang, 'moneyOut'),
          value: expenseMillimes,
          fraction: frac(expenseMillimes),
          color: AppColors.expense,
          glyph: '−',
        ),
      ],
    );
  }

  Widget _bar(
    BuildContext context, {
    required String label,
    required int value,
    required double fraction,
    required Color color,
    required String glyph,
  }) {
    // Glyph ownership moved into MoneyText; keep the explicit color/weight
    // contract identical to the previous design.
    final type = glyph == '+' ? 'income' : 'expense';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            MoneyText(
              millimes: value,
              lang: lang,
              type: type,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 12,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}
