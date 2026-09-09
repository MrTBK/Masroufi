package com.masroufi.app

/**
 * Savings-goal widget variant (Track 7).
 *
 * Same implementation as [MasroufiWidgetProvider] (inherited onUpdate,
 * same RemoteViews layout, same Dart-pushed prefs) with a separate
 * manifest entry so it appears as its own picker item ("Masroufi
 * Savings"). A subclass is required because the manifest merger rejects
 * two receivers declaring the same class name.
 */
class MasroufiSavingsWidgetProvider : MasroufiWidgetProvider()
