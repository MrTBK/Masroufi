import 'package:flutter/material.dart';

/// Centralized wallet-card styling (spec §15-17).
/// SQLite stores only stable string keys ([colorKey], [design]);
/// widgets resolve colors/patterns here. No brand logos, no gradients
/// excess: solid tonal surfaces derived from [ColorScheme].
abstract final class WalletStyles {
  static const List<String> colors = [
    'teal',
    'blue',
    'purple',
    'orange',
    'slate',
  ];

  static const List<String> designs = ['classic', 'modern', 'minimal'];

  static bool isKnownColor(String? key) => colors.contains(key);
  static bool isKnownDesign(String? key) => designs.contains(key);

  /// Card surface + on-surface pair for a [colorKey] in [brightness].
  /// Derived from fixed swatches so cards stay readable in dark mode.
  static (Color bg, Color fg) colorsFor(
    BuildContext context,
    String? colorKey,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (colorKey) {
      case 'blue':
        return dark
            ? (const Color(0xFF1E3A5F), const Color(0xFFBFDBFE))
            : (const Color(0xFFDBEAFE), const Color(0xFF1E3A8A));
      case 'purple':
        return dark
            ? (const Color(0xFF3B2A5D), const Color(0xFFE9D5FF))
            : (const Color(0xFFEDE9FE), const Color(0xFF4C1D95));
      case 'orange':
        return dark
            ? (const Color(0xFF5B3413), const Color(0xFFFED7AA))
            : (const Color(0xFFFFEDD5), const Color(0xFF7C2D12));
      case 'slate':
        return dark
            ? (const Color(0xFF1E293B), const Color(0xFFCBD5E1))
            : (const Color(0xFFE2E8F0), const Color(0xFF334155));
      case 'teal':
      default:
        return dark
            ? (const Color(0xFF0B3D2E), const Color(0xFFA7F3D0))
            : (const Color(0xFFD1FAE5), const Color(0xFF065F46));
    }
  }
}
