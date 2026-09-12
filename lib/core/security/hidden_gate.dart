import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../l10n/strings.dart';
import 'app_lock.dart';
import '../../features/lock/lock_page.dart';

/// Per-action biometric gate for hidden balances (Track 8).
///
/// Reuses the existing lock stack ([PinStore]/[BioAuth]): unmasking a
/// hidden wallet (or the global eye) challenges with biometrics first,
/// falling back to PIN verification. Pure decision ([needsAuth]) is
/// unit-tested; the async sheet ([ensureUnlocked]) is UI-thin.
///
/// Gate paths:
/// - no hidden content involved → no challenge (false).
/// - hidden involved + no PIN set → allow (nothing to prove against;
///   the global lock itself is unset).
/// - hidden involved + PIN set → biometric try, else PIN dialog.
abstract final class HiddenGate {
  /// Pure: should this tap challenge? [revealsHidden] true when the
  /// action would unmask per-wallet or global hidden balances.
  static bool needsAuth({
    required bool revealsHidden,
    required bool hasPin,
  }) => revealsHidden && hasPin;

  /// UI: returns true when the action may proceed. Never throws.
  /// PRO-gated like the lock itself: non-PRO installs never challenge.
  static Future<bool> ensureUnlocked(
    BuildContext context,
    WidgetRef ref, {
    required bool revealsHidden,
  }) async {
    try {
      if (!ref.read(isProProvider)) return true;
      final hasPin = await ref.read(pinStoreProvider).hasPin();
      if (!needsAuth(revealsHidden: revealsHidden, hasPin: hasPin)) {
        return true;
      }
      final lang = ref.read(languageProvider);
      // Biometric first (best-effort, hardware-gated).
      try {
        if (await ref.read(settingsRepoProvider).bioEnabled()) {
          final ok = await ref
              .read(bioAuthProvider)
              .authenticate(Strings.get(lang, 'unlockHidden'));
          if (ok) return true;
        }
      } catch (_) {}
      // PIN fallback (proof-of-presence dialog from the lock stack).
      if (!context.mounted) return false;
      return await showPinVerify(context: context, ref: ref);
    } catch (_) {
      return false;
    }
  }
}
