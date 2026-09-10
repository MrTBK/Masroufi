/// On-device smart-categorize suggestions (P4, no network).
///
/// Keyword → category nameKey map for Tunisian merchants (Café, Taxi,
/// Louage, STEG, SONEDE…). The add-sheet calls [suggest] with the note;
/// the user always confirms — never auto-assigns. Pure, tested.
abstract final class SmartCategorize {
  static const Map<String, String> keywords = {
    'cafe': 'cat_cafe',
    'café': 'cat_cafe',
    'kahwa': 'cat_cafe',
    'قهوة': 'cat_cafe',
    'taxi': 'cat_taxi',
    'تاكسي': 'cat_taxi',
    'louage': 'cat_louage',
    'لواج': 'cat_louage',
    'steg': 'cat_steg',
    'ستاغ': 'cat_steg',
    'sonede': 'cat_sonede',
    'صوناد': 'cat_sonede',
    'internet': 'cat_internet',
    'انترنت': 'cat_internet',
    'topnet': 'cat_internet',
    'ooredoo': 'cat_internet',
    'telecom': 'cat_internet',
    'carrefour': 'cat_groceries',
    'aziza': 'cat_groceries',
    'mg': 'cat_groceries',
    'monoprix': 'cat_groceries',
    'pharmacie': 'cat_health',
    'صيدلية': 'cat_health',
    'restaurant': 'cat_restaurant',
    'مطعم': 'cat_restaurant',
    'essence': 'cat_fuel',
    'بنزين': 'cat_fuel',
    'shell': 'cat_fuel',
    'total': 'cat_fuel',
  };

  /// Best nameKey suggestion for [note], or null when no keyword hits.
  static String? suggest(String note) {
    final n = note.toLowerCase().trim();
    if (n.isEmpty) return null;
    for (final e in keywords.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return null;
  }
}
