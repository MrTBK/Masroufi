import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/brand.dart';
import '../../core/l10n/strings.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_theme.dart';

/// App-lock UI (§34): PIN pad, lock gate, lifecycle-driven relock.
/// The gate overlays the whole app (router untouched): when
/// [lockedProvider] is true, nothing behind is visible or tappable.

/// Root wrapper: shows [LockPage] over [child] while locked and
/// relocks on return-from-background past the configured timeout.
class AppLockScope extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockScope({super.key, required this.child});

  @override
  ConsumerState<AppLockScope> createState() => _AppLockScopeState();
}

class _AppLockScopeState extends ConsumerState<AppLockScope>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final ref = this.ref;
      if (ref.read(lockedProvider)) return;
      ref.read(settingsRepoProvider).lockTimeout().then((timeout) {
        if (!mounted) return;
        if (shouldRelock(
          lockEnabled: ref.read(lockEnabledProvider),
          backgroundedAt: _backgroundedAt,
          timeoutSec: timeout,
          now: DateTime.now(),
        )) {
          ref.read(lockedProvider.notifier).state = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockedProvider);
    final enabled = ref.watch(lockEnabledProvider);
    if (locked && enabled) return const LockPage();
    return widget.child;
  }
}

/// Full-screen unlock: brand mark, PIN dots + pad, biometric shortcut.
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  bool _wrong = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _initBio();
  }

  Future<void> _initBio() async {
    final on = await ref
        .read(settingsRepoProvider)
        .bioEnabled()
        .catchError((_) => false);
    if (!mounted || !on) return;
    final can = await ref.read(bioAuthProvider).canCheck;
    if (!mounted) return;
    setState(() => _bioAvailable = can);
    // Offer biometrics immediately on cold start; failure just stays
    // on the PIN pad (never unlocks, never crashes).
    if (can) _tryBio(auto: true);
  }

  Future<void> _tryBio({bool auto = false}) async {
    final lang = ref.read(languageProvider);
    final ok = await ref
        .read(bioAuthProvider)
        .authenticate(Strings.get(lang, 'unlockApp'));
    if (!mounted) return;
    if (ok) {
      ref.read(lockedProvider.notifier).state = false;
    } else if (!auto) {
      setState(() => _wrong = true);
    }
  }

  Future<void> _submit(String pin) async {
    final ok = await ref.read(pinStoreProvider).checkPin(pin);
    if (!mounted) return;
    if (ok) {
      ref.read(lockedProvider.notifier).state = false;
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(
                  Icons.lock,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                  semanticLabel: Strings.get(lang, 'appLock'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                Brand.nameFor(lang),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _wrong
                    ? Strings.get(lang, 'wrongPin')
                    : Strings.get(lang, 'enterPin'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _wrong
                      ? Theme.of(context).colorScheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PinPad(
                onComplete: (pin) {
                  setState(() => _wrong = false);
                  _submit(pin);
                },
              ),
              if (_bioAvailable) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _tryBio(),
                  icon: const Icon(Icons.fingerprint),
                  label: Text(Strings.get(lang, 'useBiometrics')),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4-digit numeric pad. Calls [onComplete] exactly once per full entry,
/// then clears itself for the next attempt.
class PinPad extends StatefulWidget {
  final ValueChanged<String> onComplete;
  const PinPad({super.key, required this.onComplete});

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _press(String digit) {
    if (_pin.length >= 4) return;
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      final done = _pin;
      // Clear before notifying so a rejected attempt restarts clean.
      setState(() => _pin = '');
      widget.onComplete(done);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in row)
                SizedBox(
                  width: 88,
                  height: 64,
                  child: key.isEmpty
                      ? const SizedBox.shrink()
                      : key == '⌫'
                      ? IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: _backspace,
                        )
                      : TextButton(
                          onPressed: () => _press(key),
                          child: Text(
                            key,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Proof-of-presence sheet: verifies the current PIN and changes
/// nothing. Returns true only on a correct entry (used before removal).
Future<bool> showPinVerify({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final lang = ref.read(languageProvider);
  var wrong = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: StatefulBuilder(
          builder: (c, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                wrong
                    ? Strings.get(lang, 'wrongPin')
                    : Strings.get(lang, 'enterPin'),
                style: Theme.of(c).textTheme.titleMedium?.copyWith(
                  color: wrong ? Theme.of(c).colorScheme.error : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PinPad(
                onComplete: (pin) async {
                  final good = await ref.read(pinStoreProvider).checkPin(pin);
                  if (!c.mounted) return;
                  if (good) {
                    Navigator.pop(c, true);
                  } else {
                    setS(() => wrong = true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

/// PIN setup sheet (create or change): enter → confirm → mismatch loops
/// back to entry. Returns true when a new PIN was stored.
Future<bool> showPinSetup({
  required BuildContext context,
  required WidgetRef ref,
  required bool verifyOld,
}) async {
  final lang = ref.read(languageProvider);
  String? first;
  var confirmStep = false;
  var mismatch = false;
  var needVerify = verifyOld;
  final done = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(c).viewInsets.bottom + AppSpacing.lg,
        ),
        child: StatefulBuilder(
          builder: (c, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mismatch
                    ? Strings.get(lang, 'pinMismatch')
                    : confirmStep
                    ? Strings.get(lang, 'confirmPin')
                    : Strings.get(lang, 'enterPin'),
                style: Theme.of(c).textTheme.titleMedium?.copyWith(
                  color: mismatch ? Theme.of(c).colorScheme.error : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PinPad(
                onComplete: (pin) async {
                  if (needVerify && first == null && !confirmStep) {
                    final ok = await ref.read(pinStoreProvider).checkPin(pin);
                    if (!c.mounted) return;
                    if (!ok) {
                      setS(() => mismatch = true);
                      return;
                    }
                    setS(() {
                      mismatch = false;
                      needVerify = false;
                    });
                    return;
                  }
                  if (!confirmStep) {
                    setS(() {
                      first = pin;
                      confirmStep = true;
                      mismatch = false;
                    });
                    return;
                  }
                  if (pin != first) {
                    setS(() {
                      mismatch = true;
                      confirmStep = false;
                      first = null;
                    });
                    return;
                  }
                  await ref.read(pinStoreProvider).setPin(pin);
                  ref.read(lockEnabledProvider.notifier).state = true;
                  if (c.mounted) Navigator.pop(c, true);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return done == true;
}
