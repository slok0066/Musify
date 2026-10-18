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
}
