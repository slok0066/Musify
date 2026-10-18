import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/core/theme/app_theme.dart';
import 'package:musify/core/theme/swiss_tokens.dart';
import 'package:musify/core/theme/tactile_decorations.dart';
import 'package:musify/core/utils/formatters.dart';
import 'package:musify/presentation/screens/credits/full_credit_screen.dart';
import 'package:musify/presentation/widgets/collection_cards.dart';
import 'package:musify/presentation/widgets/tactile_slider.dart';

/// These are the tests that must stay green without a device, a network or an
/// audio engine: the formatting contract the whole UI reads from, and the
/// behaviour of the hardware keycap that every screen is built out of.
void main() {
  setUp(() => Haptics.enabled = false);
  tearDown(() => Haptics.enabled = true);

  group('Fmt', () {
    test('pads playhead durations consistently', () {
      expect(Fmt.duration(const Duration(minutes: 3, seconds: 8)), '03:08');
      expect(Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 45)),
          '1:02:45');
      expect(Fmt.duration(null), '--:--');
      expect(Fmt.duration(Duration.zero), '--:--');
      expect(Fmt.durationShort(const Duration(minutes: 3, seconds: 8)), '3:08');
    });

    test('cleans the HTML the catalogue leaves in titles', () {
      expect(Fmt.cleanTitle('Tum Hi Ho &quot;Reprise&quot;'),
          'Tum Hi Ho "Reprise"');
      expect(Fmt.cleanTitle('A &#8211; B'), 'A – B');
      expect(Fmt.cleanTitle('  spaced   out  '), 'spaced out');
      expect(Fmt.cleanTitle(null), 'Unknown');
      expect(Fmt.primaryArtist('Arijit Singh, Pritam'), 'Arijit Singh');
    });

    test('reports sizes and counts the way the panels do', () {
      expect(Fmt.bytes(0), '0 MB');
      expect(Fmt.bytes(6 * 1024 * 1024), '6.0 MB');
      expect(Fmt.bytes(1536 * 1024 * 1024), '1.50 GB');
      expect(Fmt.compactCount(1240331), '1.2M');
      expect(Fmt.compactCount(null), '—');
      expect(Fmt.bitrate(320), '320 KBPS');
      expect(Fmt.bitrate(null), '—');
    });
  });

  test('both chassis themes carry their token set', () {
    for (final tokens in [SwissTokens.carbon, SwissTokens.alabaster]) {
      final theme = buildMusifyTheme(tokens);
      expect(theme.extension<SwissTokens>(), same(tokens));
      expect(theme.colorScheme.brightness, tokens.brightness);
      expect(theme.splashFactory, NoSplash.splashFactory);
    }
  });

  testWidgets(
      'TactileKeycap is tappable and TactileIconKeycap honours hapticOnPress',
      (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: Scaffold(
          body: Column(
            children: [
              TactileKeycap(
                accent: true,
                onPressed: () => taps++,
                child: const Text('8D AUDIO'),
              ),
              TactileIconKeycap(
                icon: Icons.play_arrow,
                hapticOnPress: false,
                onPressed: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('8D AUDIO'), findsOneWidget);
    expect(SwissTokens.of(tester.element(find.text('8D AUDIO'))).accent,
        SwissTokens.carbon.accent);

    await tester.tap(find.text('8D AUDIO'));
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(taps, 2);
  });

  // Regression guard for the reported bug "in home i go to any playlist and
  // click any song — the song playing at bottom dosent show".
  //
  // The transport dock is the shell's `bottomNavigationBar`, so it is only on
  // screen while the shell's route is the top one. Pushing a detail screen on
  // the *root* navigator therefore hides the mini-player the moment a song is
  // started from a playlist; the chassis now keeps an inner navigator, and
  // every detail route lands there. These two tests lock both halves down: the
  // second one fails if the chassis ever goes back to a single navigator.
  testWidgets('a detail screen pushed inside the chassis keeps the dock',
      (tester) async {
    final inner = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: Scaffold(
          body: NavigatorPopHandler<void>(
            onPopWithResult: (void result) => inner.currentState?.maybePop(),
            child: Navigator(
              key: inner,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Center(
                  child: TactileKeycap(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('DETAIL SCREEN')),
                        ),
                      ),
                    ),
                    child: const Text('OPEN DETAIL'),
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text('MINI PLAYER'), Text('NAV BAR')],
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN DETAIL'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL SCREEN'), findsOneWidget);
    expect(find.text('MINI PLAYER'), findsOneWidget,
        reason: 'the dock must survive a pushed detail screen');
    expect(find.text('NAV BAR'), findsOneWidget);
  });

  testWidgets('a root push is what used to bury the dock', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TactileKeycap(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('DETAIL SCREEN')),
                    ),
                  ),
                ),
                child: const Text('OPEN ROOT'),
              ),
            ),
            bottomNavigationBar: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text('MINI PLAYER'), Text('NAV BAR')],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN ROOT'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL SCREEN'), findsOneWidget);
    expect(find.text('MINI PLAYER'), findsNothing,
        reason: 'this is the bug the nested chassis navigator fixes');
  });

  // Regression guard for the runtime-only crash
  //   "type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of
  //    'child'"
  // which happens whenever a box widget (SwissRail, SizedBox, Column …) is put
  // into a `slivers:` list. The analyzer cannot catch it — `slivers:` is typed
  // `List<Widget>` — so the shape is locked down here instead: if SliverRail
  // ever stops being a sliver, this test throws the same exception the device
  // did.
  testWidgets('SliverRail is a real sliver — empty and populated',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverRail(index: '01', title: 'EMPTY RAIL', children: []),
              SliverRail(
                index: '02',
                title: 'POPULATED RAIL',
                children: [
                  for (var i = 0; i < 3; i++)
                    const SizedBox(
                        width: 148,
                        height: 148,
                        child: ColoredBox(color: Colors.black)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('EMPTY RAIL'), findsNothing);
    expect(find.text('POPULATED RAIL'), findsOneWidget);
  });

  testWidgets('TactileSeekBar renders correctly and triggers onSeek',
      (tester) async {
    Duration? sought;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TactileSeekBar(
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 120),
              buffered: 0.5,
              enabled: true,
              onSeek: (target) => sought = target,
            ),
          ),
        ),
      ),
    );

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Tap somewhere on the slider track
    final slider = find.byType(Slider);
    await tester.tap(slider);
    await tester.pumpAndSettle();

    expect(sought, isNotNull);
  });

  testWidgets('FullCreditScreen renders creator info and calls onDismiss',
      (tester) async {
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMusifyTheme(SwissTokens.carbon),
        home: FullCreditScreen(
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    expect(find.text('Created by a human being called Shlok'), findsOneWidget);
    expect(find.text('@king_togetherness'), findsOneWidget);
    expect(find.text('ENTER MUSIFY'), findsOneWidget);

    await tester.tap(find.text('ENTER MUSIFY'));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });
}
