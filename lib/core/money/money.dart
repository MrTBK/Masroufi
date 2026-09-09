/// Money model: TND with millimes. All amounts are [int] millimes.
/// 10.500 TND == 10500 millimes. Never use double for financial math.
abstract final class Money {
  static const int millimesPerUnit = 1000;

  /// Parse user input like "12.500", "12,500", "1,250.500", "1 250.500".
  /// The LAST separator is treated as the decimal mark.
  /// Throws [FormatException] on invalid input.
  static int parse(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) throw const FormatException('empty amount');
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (s.isEmpty || !RegExp(r'[0-9]').hasMatch(s)) {
      throw const FormatException('invalid amount');
    }
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final lastSep = lastDot > lastComma ? lastDot : lastComma;
    String intPart;
    String fracPart = '';
    if (lastSep < 0) {
      intPart = s;
    } else {
      intPart = s.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
      fracPart = s.substring(lastSep + 1).replaceAll(RegExp(r'[.,]'), '');
    }
    if (intPart.isEmpty) intPart = '0';
    if (fracPart.length > 3) {
      // Round half up beyond millime precision.
      final extra = fracPart.substring(3);
      fracPart = fracPart.substring(0, 3);
      if (extra.isNotEmpty && int.parse(extra[0]) >= 5) {
        var f = int.parse(fracPart) + 1;
        if (f >= 1000) {
          intPart = (int.parse(intPart) + 1).toString();
          f = 0;
        }
        fracPart = f.toString().padLeft(3, '0');
      }
    }
    fracPart = fracPart.padRight(3, '0');
    final value = int.parse(intPart) * millimesPerUnit + int.parse(fracPart);
    if (value <= 0) throw const FormatException('amount must be positive');
    return negative ? -value : value;
  }

  /// Format millimes, e.g. 12500 -> "12.500 د.ت" (ar) / "12.500 TND".
  ///
  /// Raw ASCII, bidi-UNSAFE: never interpolate directly into RTL sentences.
  /// UI code must use [inline] (embedded amounts) or the `MoneyText`
  /// widget (standalone amounts). Storage/CSV/tests keep using this.
  static String format(int millimes, {String lang = 'en'}) {
    final negative = millimes < 0;
    final v = millimes.abs();
    final units = v ~/ millimesPerUnit;
    final frac = (v % millimesPerUnit).toString().padLeft(3, '0');
    final grouped = _groupThousands(units.toString());
    final suffix = lang == 'ar' ? 'د.ت' : 'TND';
    return '${negative ? '-' : ''}$grouped.$frac $suffix';
  }

  /// Bidi-safe amount for embedding inside mixed-direction sentences
  /// (Arabic + numbers + currency). Wraps [format] in LRI/PDI isolates
  /// (U+2066/U+2069) so the sign stays attached to the number and the
  /// currency never jumps sides. Pure int math; no doubles.
  static String inline(int millimes, {String lang = 'en'}) =>
      '\u2066${format(millimes, lang: lang)}\u2069';

  static String _groupThousands(String digits) {
    final buf = StringBuffer();
    var count = 0;
    for (var i = digits.length - 1; i >= 0; i--) {
      buf.write(digits[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write(',');
        count = 0;
      }
    }
    return buf.toString().split('').reversed.join();
  }
}
