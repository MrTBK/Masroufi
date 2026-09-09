import 'package:flutter/material.dart';

import '../icons/category_icons.dart';
import '../icons/category_visuals.dart';
import '../l10n/strings.dart';
import '../utils/haptics.dart';
import '../money/money.dart';
import '../theme/app_theme.dart';

/// Reusable design primitives (§17). All screens compose these instead of
/// duplicating styling. Brand colors stay in [AppColors]; sizes in
/// [AppSpacing]/[AppRadius].
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: card,
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Central money display (owns ALL bidi responsibility).
/// Standalone amounts everywhere must use this, never raw `Text` +
/// `Money.format`: the whole run is forced LTR so `-4,420.500 د.ت`
/// renders with the sign attached in en/fr/ar, light/dark, RTL/LTR.
///
/// Types: expense "− 5.500 TND", income "+ 2.500 TND", transfer "⇄ 500",
/// neutral = signed value, no glyph, inherited ink color (totals,
/// balances, budgets — anything that can be negative, e.g. remaining).
/// Typed modes format the absolute value + glyph; neutral formats the
/// signed value via `Money.format` (its `-` included when negative).
class MoneyText extends StatelessWidget {
  final int millimes;
  final String lang;
  final String type; // expense | income | transfer | neutral
  final TextStyle? style;
  final TextAlign? textAlign;
  const MoneyText({
    super.key,
    required this.millimes,
    required this.lang,
    required this.type,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    final (glyph, color, value) = switch (type) {
      'expense' => ('−', AppColors.expense, millimes.abs()),
      'income' => ('+', AppColors.income, millimes.abs()),
      'transfer' => ('⇄', AppColors.transfer, millimes.abs()),
      _ => ('', null, millimes),
    };
    final text = glyph.isEmpty
        ? Money.format(value, lang: lang)
        : '$glyph ${Money.format(value, lang: lang)}';
    // Typed amounts get emphasis; neutral inherits the caller's style
    // untouched (weight included) so totals keep their designed type.
    final effective = glyph.isEmpty
        ? base
        : base?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        textAlign: textAlign,
        style: effective,
        semanticsLabel: text,
      ),
    );
  }
}

/// Tinted circular icon resolved from a stored string key (§7-9).
/// Colors come from the single centralized [CategoryVisuals] registry:
/// the same key renders identically on every screen, in both brightnesses.
class CategoryAvatar extends StatelessWidget {
  final String? iconKey;
  final double radius;
  final String? semanticLabel;
  const CategoryAvatar({
    super.key,
    required this.iconKey,
    this.radius = 22,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: CategoryVisuals.backgroundOf(context, iconKey),
      foregroundColor: CategoryVisuals.foregroundOf(context, iconKey),
      child: Icon(
        CategoryIcons.iconFor(iconKey),
        size: radius,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// Neutral wallet avatar, deliberately distinct from colorful category
/// avatars: wallets share one tonal identity keyed off the color scheme.
class WalletAvatar extends StatelessWidget {
  final String? iconKey;
  final double radius;
  final String? semanticLabel;
  const WalletAvatar({
    super.key,
    required this.iconKey,
    this.radius = 22,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.tertiaryContainer,
      foregroundColor: scheme.onTertiaryContainer,
      child: Icon(
        CategoryIcons.iconFor(iconKey),
        size: radius,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// One horizontal category row: avatar + name + optional secondary info +
/// trailing action. No per-item cards — screens wrap the list, not the row.
class CategoryListTile extends StatelessWidget {
  final String? iconKey;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const CategoryListTile({
    super.key,
    required this.iconKey,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: CategoryAvatar(iconKey: iconKey, semanticLabel: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Masked amount for hidden balances: display-only, never affects math.
class HiddenBalance extends StatelessWidget {
  final TextStyle? style;
  final String semanticLabel;
  const HiddenBalance({super.key, this.style, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Text(
      '••••••••',
      style: style ?? Theme.of(context).textTheme.titleMedium,
      semanticsLabel: semanticLabel,
    );
  }
}

/// Eye toggle for balance visibility. Pure presentation control.
class VisibilityToggle extends StatelessWidget {
  final bool hidden;
  final ValueChanged<bool> onChanged;
  final String hideLabel;
  final String showLabel;
  const VisibilityToggle({
    super.key,
    required this.hidden,
    required this.onChanged,
    required this.hideLabel,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: hidden ? showLabel : hideLabel,
      icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
      onPressed: () => onChanged(!hidden),
    );
  }
}

/// Compact icon-selection grid with an unmistakable selected state
/// (primary ring + check badge). Stores keys only, never IconData.
class IconPickerGrid extends StatelessWidget {
  final List<String> keys;
  final String selected;
  final ValueChanged<String> onSelected;
  const IconPickerGrid({
    super.key,
    required this.keys,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final key in keys)
          Semantics(
            button: true,
            selected: key == selected,
            label: key,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => onSelected(key),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: key == selected
                        ? scheme.primary
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CategoryAvatar(
                      iconKey: key,
                      radius: 20,
                      semanticLabel: key,
                    ),
                    if (key == selected)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.check,
                            size: 12,
                            color: scheme.onPrimary,
                            semanticLabel: key,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Selectable wallet card with balance: used for income destination
/// ("Money goes to") and transfer source/destination. Selected card gets
/// a primary outline; hidden balances render masked.
class WalletSelectCard extends StatelessWidget {
  final String iconKey;
  final String name;
  final int? balanceMillimes;
  final bool masked;
  final String lang;
  final String maskedLabel;
  final bool selected;
  final VoidCallback onTap;
  const WalletSelectCard({
    super.key,
    required this.iconKey,
    required this.name,
    required this.balanceMillimes,
    required this.masked,
    required this.lang,
    required this.maskedLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              WalletAvatar(iconKey: iconKey, semanticLabel: name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    if (masked)
                      HiddenBalance(
                        semanticLabel: maskedLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else if (balanceMillimes != null)
                      MoneyText(
                        millimes: balanceMillimes!,
                        lang: lang,
                        type: 'neutral',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                semanticLabel: name,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Polished reusable transaction row (§10): icon, title, subtitle
/// (relative date · wallet), amount with type glyph + color.
class TransactionTile extends StatelessWidget {
  final String? iconKey;
  final String title;
  final String subtitle;
  final int millimes;
  final String lang;
  final String type;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const TransactionTile({
    super.key,
    required this.iconKey,
    required this.title,
    required this.subtitle,
    required this.millimes,
    required this.lang,
    required this.type,
    this.onTap,
    this.onLongPress,
  });

  IconData get _typeGlyph => type == 'expense'
      ? Icons.remove
      : type == 'income'
      ? Icons.add
      : Icons.swap_horiz;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: CategoryAvatar(iconKey: iconKey, semanticLabel: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _typeGlyph,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            semanticLabel: type,
          ),
          const SizedBox(width: 4),
          MoneyText(millimes: millimes, lang: lang, type: type),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Destructive-action confirmation with explicit labels.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            Haptics.confirm();
            Navigator.pop(c, true);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Localized "Month Year" not available without date-symbol data at this
/// layer; screens pass preformatted headers. Kept minimal per YAGNI.
///
/// Raw bidi-unsafe string: call sites must render it inside an explicit
/// LTR [Directionality] (the "/" migrates in RTL paragraphs otherwise).
String budgetFraction(int spent, int total, String lang) =>
    '${Money.format(spent, lang: lang)} / ${Money.format(total, lang: lang)}';

/// Standardized progress bar with over-budget error color + text pct.
class BudgetBar extends StatelessWidget {
  final int spentMillimes;
  final int totalMillimes;
  final String lang;
  const BudgetBar({
    super.key,
    required this.spentMillimes,
    required this.totalMillimes,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final pct = totalMillimes <= 0
        ? 0.0
        : (spentMillimes / totalMillimes).clamp(0.0, 1.0);
    final over = spentMillimes > totalMillimes;
    // Approaching (≥80%, same threshold as notifications): theme tertiary
    // warns before the error state; over stays error + ⚠.
    final approaching = !over && totalMillimes > 0 && pct >= 0.8;
    final color = over
        ? Theme.of(context).colorScheme.error
        : approaching
        ? Theme.of(context).colorScheme.tertiary
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: pct,
          minHeight: 10,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          '${over ? '⚠ ' : ''}${(pct * 100).toStringAsFixed(0)}% '
          '${Strings.get(lang, 'used')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
