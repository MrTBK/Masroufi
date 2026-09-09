import 'package:flutter/material.dart';

/// Deterministic category visuals: every stored icon key maps to ONE
/// background/foreground pair per brightness. The same category looks
/// identical in Categories, Add Expense/Income, History, Dashboard,
/// Reports and Budget — there is exactly one definition.
///
/// Colors are derived from fixed [MaterialColor] swatches (light bg =
/// shade100 / fg = shade800, dark bg = shade900 / fg = shade200) so
/// avatars stay readable in dark mode without muddy opacity hacks.
/// Category color carries NO financial meaning; expense/income semantics
/// stay typographic (see [MoneyText]).
class CategoryVisual {
  final Color lightBg;
  final Color lightFg;
  final Color darkBg;
  final Color darkFg;
  const CategoryVisual({
    required this.lightBg,
    required this.lightFg,
    required this.darkBg,
    required this.darkFg,
  });
}

abstract final class CategoryVisuals {
  static CategoryVisual visualFor(String? key) => _map[key] ?? _fallback;

  static Color backgroundOf(BuildContext context, String? key) {
    final v = visualFor(key);
    return Theme.of(context).brightness == Brightness.dark
        ? v.darkBg
        : v.lightBg;
  }

  static Color foregroundOf(BuildContext context, String? key) {
    final v = visualFor(key);
    return Theme.of(context).brightness == Brightness.dark
        ? v.darkFg
        : v.lightFg;
  }

  static CategoryVisual _v(MaterialColor s) => CategoryVisual(
    lightBg: s.shade100,
    lightFg: s.shade800,
    darkBg: s.shade900,
    darkFg: s.shade200,
  );

  static const _fallback = CategoryVisual(
    lightBg: Color(0xFFE2E8F0),
    lightFg: Color(0xFF334155),
    darkBg: Color(0xFF1E293B),
    darkFg: Color(0xFFCBD5E1),
  );

  static final Map<String, CategoryVisual> _map = {
    // Cash & wallets.
    'cash': _v(Colors.green),
    'bank': _v(Colors.blue),
    'card': _v(Colors.blueGrey),
    'savings': _v(Colors.teal),
    // Income.
    'salary': _v(Colors.lightGreen),
    'freelance': _v(Colors.cyan),
    'allowance': _v(Colors.lime),
    'investment': _v(Colors.green),
    'refund': _v(Colors.deepPurple),
    'other_income': _v(Colors.grey),
    'gift': _v(Colors.pink),
    // Food & drink.
    'coffee': _v(Colors.brown),
    'restaurant': _v(Colors.red),
    'fastfood': _v(Colors.orange),
    'shopping_cart': _v(Colors.green),
    // Transport.
    'taxi': _v(Colors.amber),
    'louage': _v(Colors.orange),
    'bus': _v(Colors.lightBlue),
    'directions_bus': _v(Colors.blue),
    'metro': _v(Colors.indigo),
    'tram': _v(Colors.indigo),
    'car': _v(Colors.blueGrey),
    'travel': _v(Colors.lightBlue),
    'fuel': _v(Colors.deepOrange),
    // Home & utilities.
    'bolt': _v(Colors.yellow),
    'electricity': _v(Colors.yellow),
    'steg': _v(Colors.yellow),
    'water': _v(Colors.cyan),
    'sonede': _v(Colors.cyan),
    'wifi': _v(Colors.teal),
    'internet': _v(Colors.teal),
    'phone': _v(Colors.purple),
    'mobile': _v(Colors.purple),
    'home': _v(Colors.lime),
    'rent': _v(Colors.grey),
    // Life.
    'shirt': _v(Colors.pink),
    'clothing': _v(Colors.pink),
    'devices': _v(Colors.blueGrey),
    'electronics': _v(Colors.blueGrey),
    'groceries': _v(Colors.green),
    'health': _v(Colors.red),
    'entertainment': _v(Colors.deepPurple),
    'gym': _v(Colors.lightGreen),
    'book': _v(Colors.indigo),
    'subscription': _v(Colors.grey),
    'transfer': _v(Colors.blue),
    'other': _v(Colors.grey),
  };
}
