import 'package:flutter/services.dart';

/// Central haptic vocabulary (brief §11/§39). All calls are
/// best-effort: failures (tests, unsupported platforms) are swallowed
/// so feedback can never break a flow.
abstract final class Haptics {
  /// Primary actions: central `+`, saves, confirmations.
  static Future<void> tap() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Light selections: sheet rows, chips, toggles.
  static Future<void> select() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Destructive confirmations.
  static Future<void> confirm() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
