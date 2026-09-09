import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masroufi/app/providers.dart';
import 'package:masroufi/core/security/app_lock.dart';
import 'package:masroufi/data/database/app_db.dart';
import 'package:masroufi/data/repositories/settings_repo.dart';
import 'package:masroufi/features/lock/lock_page.dart';

/// App-lock tests (§34): PIN store, relock decision, lock-page unlock,
/// PIN setup mismatch loop. Platform plugins are faked (memory store +
/// FakeBio); nothing touches biometrics here. `HashedPinStore` runs
/// against an in-memory DB (pure-Dart hashing, no plugin at all).
void main() {
  group('MemoryPinStore', () {
    test('set/check/clear round-trip', () async {
      final store = MemoryPinStore();
      expect(await store.hasPin(), isFalse);
      expect(await store.checkPin('1234'), isFalse);
      await store.setPin('1234');
      expect(await store.hasPin(), isTrue);
      expect(await store.checkPin('1234'), isTrue);
      expect(await store.checkPin('0000'), isFalse);
      await store.clear();
      expect(await store.hasPin(), isFalse);
    });

    test('rejects non-4-digit PINs', () async {
      final store = MemoryPinStore();
      for (final bad in ['123', '12345', 'abcd', '12 4', '']) {
        await expectLater(store.setPin(bad), throwsArgumentError);
      }
      expect(await store.hasPin(), isFalse);
    });
  });

  group('HashedPinStore', () {
    test('salted stretched hash round-trips, salts differ', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final a = HashedPinStore(SettingsRepo(db));
      final b = HashedPinStore(SettingsRepo(db));
      await a.setPin('1234');
      expect(await a.hasPin(), isTrue);
      expect(await a.checkPin('1234'), isTrue);
      expect(await a.checkPin('0000'), isFalse);
      await b.setPin('1234');
      final rawA = await SettingsRepo(db).get(HashedPinStore.storageKey);
      // Same PIN, different salt → different stored strings.
      await a.setPin('1234');
      final rawA2 = await SettingsRepo(db).get(HashedPinStore.storageKey);
      expect(rawA, isNot(rawA2));
      expect(rawA, isNot(contains('1234')));
      await a.clear();
      expect(await a.hasPin(), isFalse);
      expect(b, isNotNull);
    });

    test('corrupt stored value fails closed', () async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepo(db);
      final store = HashedPinStore(settings);
      await settings.set(HashedPinStore.storageKey, 'garbage');
      expect(await store.checkPin('1234'), isFalse);
    });
  });

  group('shouldRelock', () {
    final now = DateTime(2026, 9, 8, 12, 0);
    test('disabled or never-backgrounded never locks', () {
      expect(
        shouldRelock(
          lockEnabled: false,
          backgroundedAt: now.subtract(const Duration(hours: 5)),
          timeoutSec: 0,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldRelock(
          lockEnabled: true,
          backgroundedAt: null,
          timeoutSec: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('timeout 0 locks immediately, grace periods respected', () {
      final bg = now.subtract(const Duration(seconds: 10));
      expect(
        shouldRelock(
          lockEnabled: true,
          backgroundedAt: bg,
          timeoutSec: 0,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldRelock(
          lockEnabled: true,
          backgroundedAt: bg,
          timeoutSec: 60,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldRelock(
          lockEnabled: true,
          backgroundedAt: now.subtract(const Duration(seconds: 61)),
          timeoutSec: 60,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('LockPage', () {
    Future<ProviderContainer> boot(WidgetTester t, MemoryPinStore store) async {
      final db = AppDb.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          pinStoreProvider.overrideWithValue(store),
          bioAuthProvider.overrideWithValue(FakeBio(available: false)),
        ],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });
      await store.setPin('1234');
      container.read(lockEnabledProvider.notifier).state = true;
      container.read(lockedProvider.notifier).state = true;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppLockScope(child: Text('HOME'))),
        ),
      );
      await t.pumpAndSettle();
      return container;
    }

    Future<void> enterPin(WidgetTester t, String pin) async {
      for (final d in pin.split('')) {
        await t.tap(find.text(d).first);
        await t.pump();
      }
      await t.pumpAndSettle();
    }

    testWidgets('correct PIN unlocks, wrong PIN stays locked', (t) async {
      final store = MemoryPinStore();
      final container = await boot(t, store);
      expect(find.text('HOME'), findsNothing); // gate holds
      await enterPin(t, '0000');
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(container.read(lockedProvider), isTrue);
      await enterPin(t, '1234');
      expect(container.read(lockedProvider), isFalse);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('PIN setup stores after confirm, mismatch loops', (t) async {
      final store = MemoryPinStore();
      final db = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          pinStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      var result = false;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (c, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showPinSetup(
                      context: c,
                      ref: ref,
                      verifyOld: false,
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('OPEN'));
      await t.pumpAndSettle();
      // Mismatch: enter 1111 then 2222 → loops without storing.
      await enterPin(t, '1111');
      await enterPin(t, '2222');
      expect(await store.hasPin(), isFalse);
      expect(find.text('PINs do not match'), findsOneWidget);
      // Correct: 5678 twice → stored.
      await enterPin(t, '5678');
      await enterPin(t, '5678');
      expect(result, isTrue);
      expect(await store.checkPin('5678'), isTrue);
    });
  });
}
