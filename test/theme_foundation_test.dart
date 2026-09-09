import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/core/theme/app_theme.dart';

void main() {
  group('theme foundation (DESIGN.md contract)', () {
    test('light scheme is light-first paper, not seed default', () {
      final t = buildLightTheme();
      expect(t.brightness, Brightness.light);
      expect(t.colorScheme.primary, AppColors.primary);
      expect(t.scaffoldBackgroundColor, AppColors.paper);
      expect(t.colorScheme.surface, Colors.white);
    });

    test('dark scheme is designed, never pure black or white', () {
      final t = buildDarkTheme();
      expect(t.brightness, Brightness.dark);
      expect(t.colorScheme.surface.toARGB32(), isNot(0xFF000000));
      expect(t.colorScheme.onSurface.toARGB32(), isNot(0xFFFFFFFF));
      expect(t.scaffoldBackgroundColor, AppColors.darkBase);
    });

    test('single type family with tuned heights', () {
      final t = buildLightTheme();
      final text = t.textTheme;
      expect(text.bodyLarge!.fontFamily, 'PlexSans');
      expect(text.displayLarge!.fontFamily, 'PlexSans');
      expect(text.bodyLarge!.height, greaterThanOrEqualTo(1.4));
      expect(text.displayLarge!.height, greaterThanOrEqualTo(1.1));
      expect(text.bodyLarge!.fontSize, greaterThanOrEqualTo(14));
    });

    test('single radius family and 52dp primary action', () {
      final t = buildLightTheme();
      final shape =
          t.filledButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        const BorderRadius.all(Radius.circular(AppRadius.md)),
      );
      expect(
        t.filledButtonTheme.style!.minimumSize!.resolve({}),
        const Size(48, 52),
      );
      expect(t.cardTheme.margin, EdgeInsets.zero);
    });
  });
}
