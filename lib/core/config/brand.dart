/// Centralized branding. Change the name here to rebrand the app.
abstract final class Brand {
  static const String nameEn = 'Masroufi';
  static const String nameAr = 'مصروفي';
  static const String nameFr = 'Masroufi';
  static const String applicationId = 'com.masroufi.app';
  static const String currencyCode = 'TND';

  static String nameFor(String lang) => switch (lang) {
    'ar' => nameAr,
    'fr' => nameFr,
    _ => nameEn,
  };
}
