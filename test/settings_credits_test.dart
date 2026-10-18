// Locks in the "welcome & credits page appears only on a first install"
// contract.
//
// The credits gate reads a single SharedPreferences boolean so that the flag
// survives even if the settings JSON is lost or corrupt. These tests pin both
// halves of that contract: the flag alone is enough, and a first install with
// nothing stored still shows the page.

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stored seen-flag suppresses the credits page even without JSON',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsService.seenCreditsKey: true,
    });

    final service = SettingsService();
    await service.load();

    expect(service.value.hasSeenCredits, isTrue);
  });

  test('a first install has nothing stored and still shows the page',
      () async {
    SharedPreferences.setMockInitialValues({});

    final service = SettingsService();
    await service.load();

    expect(service.value.hasSeenCredits, isFalse);
  });

  test('the JSON copy of the flag is honoured on its own', () async {
    SharedPreferences.setMockInitialValues({
      'musify.settings.v1': '{"hasSeenCredits":true}',
    });

    final service = SettingsService();
    await service.load();

    expect(service.value.hasSeenCredits, isTrue);
  });

  test('dismissing the page persists the seen-flag for the next launch',
      () async {
    SharedPreferences.setMockInitialValues({});

    final first = SettingsService();
    await first.load();
    expect(first.value.hasSeenCredits, isFalse);

    // What the cubit does when the user taps `ENTER MUSIFY`.
    first.update(first.value.copyWith(hasSeenCredits: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final next = SettingsService();
    await next.load();
    expect(next.value.hasSeenCredits, isTrue);
  });

  // The gate must be able to tell "the store was read and this is a first
  // install" from "the store has not been read yet" — otherwise a slow startup
  // looks like a first install on every launch, which is exactly how the
  // credits page used to reappear for existing users.
  test('a store that has not been read yet says so', () {
    final service = SettingsService();
    expect(service.isLoaded, isFalse);
  });

  test('load signals completion even when the result equals the defaults',
      () async {
    SharedPreferences.setMockInitialValues({});

    final service = SettingsService();
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.load();

    expect(service.isLoaded, isTrue);
    // The loaded value is the same const defaults object, so the notifier on
    // its own would stay silent — the gate would never hear that the store
    // was read.
    expect(notifications, greaterThanOrEqualTo(1));
  });
}
