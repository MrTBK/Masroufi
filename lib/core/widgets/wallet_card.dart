import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../icons/category_icons.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/wallet_styles.dart';
import 'design.dart';

/// Bank-card-like wallet presentation using Masroufi's own identity
/// (solid tonal surfaces, no payment-network branding).
/// Hiding masks the balance only; math always includes hidden wallets.
/// Tracked uppercase card-name spacing: the single deliberate
/// letterspacing exception, named and shared by all card text.
const double _nameTracking = 0.8;

class WalletCardView extends StatelessWidget {
  final String name;
  final String iconKey;
  final String colorKey;
  final String design;
  final int balanceMillimes;
  final bool masked;
  final String lang;
  final String? sublabel;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggleHidden;
  final bool hidden;
  const WalletCardView({
    super.key,
    required this.name,
    required this.iconKey,
    required this.colorKey,
    required this.design,
    required this.balanceMillimes,
    required this.masked,
    required this.lang,
    this.sublabel,
    this.onTap,
    this.onToggleHidden,
    required this.hidden,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = WalletStyles.colorsFor(context, colorKey);
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: design == 'minimal'
            ? Border.all(color: fg.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CategoryIcons.iconFor(iconKey),
                color: fg,
                size: 22,
                semanticLabel: name,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    letterSpacing: _nameTracking,
                  ),
                ),
              ),
              if (onToggleHidden != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    tooltip: hidden
                        ? Strings.get(lang, 'showBalance')
                        : Strings.get(lang, 'hideBalance'),
                    color: fg,
                    icon: Icon(
                      hidden ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => onToggleHidden!(!hidden),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          masked
              ? HiddenBalance(
                  semanticLabel: Strings.get(lang, 'hiddenBalance'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.bold),
                )
              : MoneyText(
                  millimes: balanceMillimes,
                  lang: lang,
                  type: 'neutral',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.bold),
                ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            sublabel ?? Brand.nameEn,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: fg.withValues(alpha: 0.75)),
          ),
          if (design == 'modern')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: card,
    );
  }
}

/// Color dot picker for the wallet dialog (keys only, no Color in DB).
class WalletColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  const WalletColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final key in WalletStyles.colors)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => onSelected(key),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                color: WalletStyles.colorsFor(context, key).$1,
                border: Border.all(
                  color: key == selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: key == selected
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color: WalletStyles.colorsFor(context, key).$2,
                      semanticLabel: key,
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
