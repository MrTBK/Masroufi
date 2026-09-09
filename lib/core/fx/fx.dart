/// Manual offline multi-currency (Track 8, display-only, no schema).
///
/// Ledger stays TND millimes. A transaction may carry its ORIGINAL foreign
/// amount ([origMinor] in foreign minor units + [origCurrency] ISO code);
/// conversion to TND uses a MANUALLY entered offline rate (KV
/// `fx_rate_<CODE>` = TND millimes per 1 foreign major unit).
///
/// Conventions (documented, int-only):
/// - TND: 3 decimals (millimes). Foreign: 2 decimals (cents) for all
///   supported codes (EUR, USD, GBP, …). No floats anywhere.
/// - tndMillimes = origMinor * rate ~/ 100.
/// - Rates are manual and may go stale: [isStale] when the rate timestamp
///   (`fx_rate_updated_at_<CODE>`) is older than 30 days or missing.
/// - Display-only: balances, budgets, analytics never read foreign
///   amounts; only the detail row shows original + converted + badge.
abstract final class Fx {
  static const supported = ['EUR', 'USD', 'GBP'];
  static const staleAfter = Duration(days: 30);

  static String rateKey(String code) => 'fx_rate_${code.toUpperCase()}';
  static String rateAtKey(String code) =>
      'fx_rate_updated_at_${code.toUpperCase()}';

  /// Int-only conversion. Throws on bad input (unknown code, non-positive).
  static int toTndMillimes({
    required int origMinor,
    required String currency,
    required int rateMillimesPerUnit,
  }) {
    final code = currency.toUpperCase();
    if (!supported.contains(code)) throw ArgumentError('unsupported $currency');
    if (origMinor <= 0) throw ArgumentError('amount');
    if (rateMillimesPerUnit <= 0) throw ArgumentError('rate');
    return origMinor * rateMillimesPerUnit ~/ 100;
  }

  /// Format foreign minor units with 2 decimals + code: 1250 → "12.50 EUR".
  static String formatOriginal(int origMinor, String currency) {
    final code = currency.toUpperCase();
    final major = origMinor ~/ 100;
    final minor = (origMinor % 100).abs().toString().padLeft(2, '0');
    return '$major.$minor $code';
  }

  /// Stale when no timestamp or older than 30 days.
  static bool isStale({required DateTime? updatedAt, required DateTime now}) {
    if (updatedAt == null) return true;
    return now.difference(updatedAt) > staleAfter;
  }

  static DateTime? parseAt(String? raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Parse foreign amount text ("12.50", "12,50") to minor units (cents,
  /// 2 decimals, half-up beyond). Throws [FormatException] when invalid.
  static int parseMinor(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) throw const FormatException('empty');
    s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final sep = lastDot > lastComma ? lastDot : lastComma;
    String intPart;
    String frac = '';
    if (sep < 0) {
      intPart = s;
    } else {
      intPart = s.substring(0, sep).replaceAll(RegExp(r'[.,]'), '');
      frac = s.substring(sep + 1).replaceAll(RegExp(r'[.,]'), '');
    }
    if (intPart.isEmpty) intPart = '0';
    if (frac.length > 2) {
      final extra = frac.substring(2);
      frac = frac.substring(0, 2);
      if (extra.isNotEmpty && int.parse(extra[0]) >= 5) {
        var f = int.parse(frac) + 1;
        if (f >= 100) {
          intPart = (int.parse(intPart) + 1).toString();
          f = 0;
        }
        frac = f.toString().padLeft(2, '0');
      }
    }
    frac = frac.padRight(2, '0');
    final v = int.parse(intPart) * 100 + int.parse(frac);
    if (v <= 0) throw const FormatException('positive');
    return v;
  }
}
