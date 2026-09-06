# Localization

Hand-rolled string tables in `lib/core/l10n/strings.dart` (no codegen step):
`AppStrings.get(lang, key)` for `en`, `fr`, `ar`.

- Arabic is first-class: `Directionality.rtl`, Material `locale: Locale('ar')`,
  mirrored layouts verified on dashboard/history/forms/dialogs/nav.
- Numbers/dates via `intl`: `NumberFormat` per locale, `DateFormat.yMMMd(locale)`.
- TND: `Money.format(millimes, locale)` -> e.g. `10.500 د.ت` (ar), `10,500 TND` style
  per locale kept simple: `10.500` + suffix `د.ت`/`TND`.
- Millime input: user types `12.500`; parsed to `12500` int. Never `double`.
- No hard-coded UI strings in widgets; category defaults use `name_key` so they
  translate automatically.
