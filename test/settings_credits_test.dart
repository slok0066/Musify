// Locks in the "welcome & credits page appears only on a first install"
// contract.
//
// The credits gate reads two independent witnesses: a SharedPreferences
// boolean and a file marker. Preferences writes are asynchronous, so a user
// who swipes the app away from recents seconds after the page paints can lose
// the write — and the page then returns on every launch. The marker is written
// *synchronously* on the first launch, before that launch's page can even
// appear, so it cannot lose that race. These tests pin the whole contract:
// either witness suppresses the page on its own, and a genuine first install
// with nothing stored still shows it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/settings_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers `getApplicationSupportDirectory` with a scratch directory so the
/// marker contract can be exercised without a device.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File marker;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('musify_credits_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    marker = File('${root.path}${Platform.pathSeparator}musify.launched');
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    if (marker.existsSync()) marker.deleteSync();
  });

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

  // Exactly the reported bug: open the app, see the page, swipe the app away
  // from recents. Every asynchronous write is lost; the synchronous marker is
  // not.
  test('a second launch is recognised even when every flag write was lost',
      () async {
    SharedPreferences.setMockInitialValues({});

    final first = SettingsService();
    await first.load();
    expect(first.value.hasSeenCredits, isFalse);
    expect(marker.existsSync(), isTrue,
        reason: 'the first launch must stamp the marker before the page shows');

    // Swipe-away: the preferences store is gone and the writes never landed.
    SharedPreferences.setMockInitialValues({});

    final second = SettingsService();
    await second.load();
    expect(second.value.hasSeenCredits, isTrue,
        reason: 'the marker alone must suppress the page on relaunch');
  });

  test('markCreditsSeenNow stamps the marker synchronously', () async {
    SharedPreferences.setMockInitialValues({});

    // The store resolves the marker directory during startup.
    await SettingsService().load();
    marker.deleteSync();

    SettingsService.markCreditsSeenNow();

    expect(marker.existsSync(), isTrue,
        reason: 'the stamp must not wait on any asynchronous write');
  });
}
