import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/providers.dart';
import '../../data/repositories/settings_repo.dart';

/// App-lock security layer (brief §34).
///
/// Threat model (offline-first, honest scope): keeps casual snoopers out
/// when the phone is shared or lost-and-glanced-at. NOT a vault against
/// a rooted device or a forensic analyst — the ledger DB itself is not
/// encrypted (documented limitation).
///
/// - PIN: stored as a salted, stretched SHA-256 hash
///   (`iterations$salt$hash` in the existing `app_settings` KV — no
///   schema migration, no native keystore plugin). The app-private DB
///   file is unreadable to other apps on non-rooted devices; stretching
///   slows offline guessing. Deliberately chosen over a keystore plugin
///   (which demanded an Android SDK bump for zero practical gain here).
/// - Biometric: OS-handled via `local_auth`; only an on/off flag is
///   persisted, never biometric data.
/// - Flags (`bio_enabled`, `lock_timeout`) live in `app_settings` too.
/// - All platform calls are try/caught: denial or missing hardware
///   degrades to PIN, never to a crash or an unlocked app.
abstract class PinStore {
  Future<bool> hasPin();
  Future<void> setPin(String pin);
  Future<bool> checkPin(String pin);
  Future<void> clear();
}

/// Production store: stretched salted hash in the app settings KV.
class HashedPinStore implements PinStore {
  static const storageKey = 'app_pin_hash_v1';
  static const _iterations = 20000;
  final SettingsRepo settings;
  HashedPinStore(this.settings);

  @override
  Future<bool> hasPin() async {
    try {
      return await settings.get(storageKey) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setPin(String pin) async {
    validate(pin);
    final salt = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    await settings.set(storageKey, _encode(salt, _stretch(pin, salt)));
  }

  @override
  Future<bool> checkPin(String pin) async {
    try {
      final stored = await settings.get(storageKey);
      if (stored == null) return false;
      final parts = stored.split(r'$');
      if (parts.length != 3) return false;
      final iterations = int.tryParse(parts[0]);
      final salt = base64Decode(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      final candidate = _stretch(pin, salt, iterations: iterations);
      return _constantEquals(base64Decode(parts[2]), candidate);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await settings.remove(storageKey);
    } catch (_) {}
  }

  static void validate(String pin) {
    if (pin.length != 4 || int.tryParse(pin) == null) {
      throw ArgumentError('PIN must be 4 digits');
    }
  }

  static String _encode(List<int> salt, List<int> hash) =>
      '$_iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';

  static List<int> _stretch(String pin, List<int> salt, {int? iterations}) {
    var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
    final n = iterations ?? _iterations;
    for (var i = 1; i < n; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return digest;
  }

  static bool _constantEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// In-memory store for widget/unit tests (never production).
class MemoryPinStore implements PinStore {
  String? _pin;
  @override
  Future<bool> hasPin() async => _pin != null;
  @override
  Future<void> setPin(String pin) async {
    HashedPinStore.validate(pin);
    _pin = pin;
  }

  @override
  Future<bool> checkPin(String pin) async => _pin != null && _pin == pin;
  @override
  Future<void> clear() async => _pin = null;
}

/// Biometric capability + prompt, abstracted for tests.
abstract class BioAuth {
  Future<bool> get canCheck;
  Future<bool> authenticate(String reason);
}

/// Production: OS biometric prompt, biometric-only (falls back to PIN UI).
class LocalAuthBio implements BioAuth {
  final LocalAuthentication _auth;
  LocalAuthBio([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> get canCheck async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Test double: scripted availability + result.
class FakeBio implements BioAuth {
  final bool available;
  final bool result;
  FakeBio({this.available = true, this.result = true});
  @override
  Future<bool> get canCheck async => available;
  @override
  Future<bool> authenticate(String reason) async => result;
}

/// Pure relock decision (unit-tested): lock when enabled and the app was
/// backgrounded longer than [timeoutSec] (0 = immediately on return).
/// Null [backgroundedAt] (never backgrounded) never locks.
bool shouldRelock({
  required bool lockEnabled,
  required DateTime? backgroundedAt,
  required int timeoutSec,
  required DateTime now,
}) {
  if (!lockEnabled || backgroundedAt == null) return false;
  return now.difference(backgroundedAt).inSeconds >= timeoutSec;
}

// Providers (overridden in tests with memory/fake variants).
final pinStoreProvider = Provider<PinStore>(
  (ref) => HashedPinStore(ref.watch(settingsRepoProvider)),
);
final bioAuthProvider = Provider<BioAuth>((ref) => LocalAuthBio());

/// Whether the vault UI is currently shown. Initialized in `main.dart`
/// from `PinStore.hasPin()`; set false on successful unlock.
final lockedProvider = StateProvider<bool>((ref) => false);

/// Whether a PIN exists (drives settings UI + relock decisions).
/// Hydrated in `main.dart`, updated on set/remove.
final lockEnabledProvider = StateProvider<bool>((ref) => false);
