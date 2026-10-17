# Musify — Implementation Log, Fix Atlas & Troubleshooting Guide

**Last updated:** 17 Oct 2026
**Host:** Windows 11 (25H2) · **Toolchain:** Flutter 3.47.7 stable · Dart 3.13.5 · Android SDK 37.0.0
**Target:** Android only (API 26 → 36, arm64-v8a + armeabi-v7a, Impeller).

> **Read this first if something breaks.** §5 is a line-by-line record of every
> compiler error this project has produced and the exact fix. §8 maps symptoms to
> causes. §9 is a widget-API cheat sheet for the custom design system, which is
> where most "named parameter isn't defined" errors come from.

---

## 0. Status board

| Item | State | Evidence |
| --- | --- | --- |
| `flutter analyze` | **0 issues** | `No issues found!` — re-run after pass 6 edits |
| `flutter test` | **69/69 passed** | `00:04 +69: All tests passed!` (five files, see §7) |
| `flutter build apk --release` | **succeeded** | `√ Built build\app\outputs\flutter-apk\app-release.apk` — 1020.8 s cold, 135.3 s incremental for the pass-6 build (§7.1) |
| APK identity | `com.musify.musify` 1.0.2 (3), minSdk 26, targetSdk 36, compileSdk 36 | `aapt2 dump badging`; build marker `1.0.2+3 · STREAM-ENGINE · 2026-10-17` in Settings ▸ ABOUT and `COPY REPORT` |
| APK ABIs | **arm64-v8a + armeabi-v7a only** — no x86/x86_64 | `aapt2`: `native-code: 'arm64-v8a' 'armeabi-v7a'`; zip inspection: 22 native libs, zero x86 entries |
| APK contents | Flutter engine + app snapshot + SoLoud + codecs for both ABIs | `libflutter.so`, `libapp.so`, `libflutter_soloud_plugin.so`, `libFLAC/ogg/opus/vorbis/vorbisenc/vorbisfile.so`, `libdartjni.so` |
| Android device run | **three passes done — 11 runtime/reported bugs found, 11 fixed** | pass 4: `RenderConstrainedBox is not a subtype of RenderSliver` (§5.4 #24–#28). Pass 5 (from the phone): no mini-player in playlists, 10–15 s to first sample, "like doesn't work" (§5.6 #29–#31). Pass 6 (from the phone): still slow to start, heart in the player, playlist import, nav ordinals, Home pills (§5.7 #32–#36). Retest pending |
| Instant playback | **progressive streaming** — first sample from the first ~100 KB, not the whole file: MP4 is demuxed to ADTS on the fly, MP3/FLAC/Ogg/WAV pass through raw | `services/mp4_aac.dart` + `MediaCache.openStream` + `PlaybackService._startProgressive`/`_feedRaw`; proven against a live 320 kbps file by `tool/adts_check.dart` (11,550 samples, alignment exact, 0 bad frames); every refusal falls back to the pass-5 download route |
| Windows desktop run | **stopped on request** | the project targets Android; Windows was only ever the dev machine for `analyze`/`test` |

**Owner decision recorded:** do **not** run `flutter run -d windows`. `flutter analyze`
and `flutter test` still execute on the Windows host (that is just the development
machine, not a shipping target).

---

## 1. Verify the project in ~60 seconds (Android only)

```bash
flutter pub get
flutter analyze --no-pub      # expect: No issues found!
flutter test                  # expect: All tests passed!  (69 tests)

flutter devices               # find your Android device id
flutter run -d <device-id>    # debug build on device

flutter build apk --release --target-platform android-arm --target-platform android-arm64
```

Useful extras:

```bash
flutter run -d <device-id> --verbose      # if the app shows no UI
adb logcat -s flutter                     # app-side prints and Dart errors
flutter clean && flutter pub get          # last resort when builds go weird
```

> First run after a `flutter clean` is slow **on purpose**: `flutter_soloud`
> compiles its native plugin (`libflutter_soloud_plugin.so` /
> `flutter_soloud_plugin.dll`) before anything can start. Expect minutes with no
> console output. That is not a hang — see §8.1.

---

## 2. Environment facts (measured, not assumed)

| Fact | Value |
| --- | --- |
| Flutter / Dart | 3.47.7 stable / 3.13.5 |
| Android SDK | `C:\Users\singh\AppData\Local\Android\sdk` (37.0.0) |
| Platforms installed | android-31, 33, 34, 35, 36, 36.1, 37.0 |
| Build-tools installed | 34.0.0, 35.0.0, 36.0.0, 36.1.0, 37.0.0 |
| Licences | `licenses/android-sdk-license` **present** (Gradle will not complain) |
| `cmdline-tools` | **missing** (`flutter doctor` warning only — Gradle does not need it) |
| NDK / CMake | installed (needed by the SoLoud native plugin) |
| Java/Kotlin target | JVM 17 (`android/app/build.gradle.kts`) |
| Gradle wrapper | standard Flutter template, AGP pinned by `settings.gradle.kts` |

---

## 3. What the app is, in one paragraph

Musify is a Spotify-class Android music app: JioSaavn catalogue at 320 kbps, a
rolling 500 MB on-disk cache plus true offline downloads, a real 8D spatial-audio
engine (LFO orbit + rear low-pass + hall reverb, retuned every 16 ms), EQ, crossfade,
sleep timer, synced lyrics, playlist import, JSON backup, and lock-screen media
controls. Visually it is Swiss minimalism (exposed 1px grid, hard corners,
monospace telemetry) crossed with tactile skeuomorphism (machined keycaps, recessed
wells, one Signal-Orange LED).

### Feature map

| Screen | Shipped behaviour |
| --- | --- |
| `01 // HOME` | Trending / New releases / Charts / Daily mixes / Genre tiles / **8D SPATIAL PICKS**, skeletons, pull-to-refresh, offline strip |
| `02 // SEARCH` | 350 ms debounced multi-search (songs, albums, artists, playlists), filter pills, recent queries, genre browser, `⋮` options sheet |
| `03 // LIBRARY` | Liked / Playlists / Downloads / Import, list ⇄ grid, create / rename / delete, per-track download progress, YouTube & Spotify URL import |
| `04 // SETTINGS` | Quality ladder, **instant play**, 8D calibration, 10-band EQ + bass boost, crossfade, storage manager + cache clear, JSON backup export/import, theme, haptics, About |
| Now Playing | Artwork, 8D keycap + calibration sheet, seek/buffer readout, transport, repeat/shuffle, queue counter, volume, FFT/waveform analyser, lyrics, queue editor, sleep timer |

---

## 4. Source inventory (use this to jump straight to a file)

```
lib/
  main.dart                        Boot: 4 s time-boxed steps, fault-card hook, post-frame audio warm-up
  app.dart                         MaterialApp, both chassis themes, app-wide BlocProviders
  core/theme/swiss_tokens.dart     SwissTokens (carbon/alabaster), SwissGrid, SwissType
  core/theme/app_theme.dart        Tokens → ThemeData (no ripples, no elevation, square corners)
  core/theme/tactile_decorations.dart  Keycaps, wells, pills, LED, hairlines, marquee, Haptics gate
  core/theme/swiss_error_card.dart Global ErrorWidget.builder (Law 4) — dependency-free
  core/build_info.dart             Build marker (kBuildLabel): Settings ▸ ABOUT + first line of COPY REPORT
  core/utils/debouncer.dart        350 ms search debounce
  core/utils/formatters.dart       Fmt.* — durations, bytes, counts, HTML entity cleaning
  data/models/track.dart           Track (+ encrypted URL, bitrate, lyrics flag)
  data/models/collection.dart      Collection + CollectionKind
  data/models/lyrics.dart          LRC parsing + timed lines
  data/models/user_playlist.dart   User playlist + mosaic artwork
  data/datasources/jiosaavn_client.dart   api.php calls, DES media-URL decryption, null-safe mapping
  data/datasources/lyrics_client.dart     LRCLIB synced lyrics
  data/datasources/artwork_client.dart    Deezer → iTunes artwork fallback
  data/datasources/playlist_importer.dart YouTube/Spotify page → JioSaavn re-match (metadata only)
  data/sources/local_store.dart    Hive + SharedPreferences, `revision` notifier
  data/repositories/music_repository.dart    Waterfall resolver, home feed, search, collections, downloads,
                                             openStream()/completedPathFor() for the progressive player
  data/repositories/library_repository.dart  Likes, playlists, downloads, backups
  services/settings_service.dart   Persisted settings + enums VisualizerMode / RepeatMode (+ instantStart)
  services/media_cache.dart        Rolling 500 MB LRU cache, offline vault, progress, prefetch,
                                   openStream() read-while-writing transfer + ByteCoverage + StreamSession
  services/mp4_aac.dart            MP4 → ADTS demuxer: moov/stbl sample table → ADTS frames (instant-play core)
  services/network_monitor.dart    connectivity_plus stream → OfflineStrip
  services/backup_service.dart     JSON export/import
  services/player/playback_service.dart  SoLoud engine: queue, shuffle, 8D orbit, EQ, crossfade, sleep timer,
                                         progressive pull-buffer path + 7 s watchdog fallback
  services/player/audio_handler.dart     audio_service adapter (Android/iOS only) + like delegate
  services/service_locator.dart    get_it wiring, bootstrapServices(), warmUpAudio(), isMobilePlatform
  presentation/navigation.dart     openNowPlaying / openCollection / openUserPlaylist / openArtist
  presentation/cubits/*            home, search, collection, library, player, settings, navigation
  presentation/shell/main_shell_screen.dart  Nested chassis Navigator + IndexedStack + SwissNavBar + toast host
  presentation/shell/mini_player_bar.dart    Docked mini player (marquee, 8D keycap)
  presentation/screens/home/home_screen.dart
  presentation/screens/search/search_screen.dart
  presentation/screens/collection/collection_detail_screen.dart
  presentation/screens/library/library_screen.dart
  presentation/screens/library/playlist_detail_screen.dart
  presentation/screens/now_playing/now_playing_screen.dart
  presentation/screens/now_playing/lyrics_bottom_sheet.dart
  presentation/screens/now_playing/queue_bottom_sheet.dart
  presentation/screens/now_playing/sleep_timer_sheet.dart
  presentation/screens/settings/settings_screen.dart
  presentation/widgets/*           screen_header, state_placeholders, swiss_artwork, collection_cards,
                                   track_list_tile, track_options_sheet, add_to_playlist_sheet,
                                   import_url_sheet, eight_d_calibration_sheet, tactile_eight_d_switch,
                                   tactile_slider, fft_visualizer, track_prefetch
tool/des_check.dart                Proof that the media-URL decryption + _96 → _320 upgrade works
tool/adts_check.dart               Proof that the MP4 → ADTS demuxer is frame-exact, against a live file
test/widget_test.dart              8 tests: Fmt, theme tokens, keycap behaviour, SliverRail-is-a-sliver,
                                   dock-survives-a-pushed-detail-screen (no device needed)
test/jiosaavn_parsing_test.dart    28 tests: Law 7 hostile JioSaavn payloads, DES fixture, 320 rewrite,
                                   Law 8 rotten Hive maps (no device needed)
test/streaming_test.dart           10 tests: range splitting, container sniffing / error-page rejection,
                                   rendition ladder, LocalStore running without boxes (no device needed)
test/mp4_aac_test.dart             17 tests: Law 7 for the demuxer — a hand-built MP4, byte-exact ADTS
                                   assembly, tail-`moov` search, ByteCoverage merge/hole arithmetic
test/media_cache_stream_test.dart   6 tests: staged sessions, overFile guards, ensure short-circuit,
                                   unreachable-URL fallback, ByteCoverage after a forward seek
prd                                The original specification (single file)
README.md                          Product overview + the one honest deviation
docs/IMPLEMENTATION_LOG.md          ← this file
```

---

## 5. Fix log — every error, its root cause, and the fix

Six passes. **Pass 1 (33 issues)** cleaned up the first sweep of the
codebase. **Pass 2 (61 issues)** looked *worse* than pass 1 for a boring reason:
`lib/presentation/navigation.dart` had broken import paths, so every screen it
imported was invisible to the analyzer. Fixing those three paths made ~40 further
errors visible at once. Expect that pattern in any Dart project: **errors in
imports mask errors in the files behind them.**

**Pass 3 is the Android build**, and it is where you find the class of error the
analyzer structurally cannot see: manifest markers, Gradle config, dependencies,
ABI filters (see #22 below).

**Pass 4 is the first run on hardware** (§5.4) — and it found something no
analyzer could: a box widget handed to a viewport. Its own lesson: *the analyzer
checks types, not render-object contracts.* Two follow-ups came out of the same
pass: writing the Law 7 tests turned up three latent defects (#25–#27) that would
have shown up as cosmetic oddities (an `UNKNOWN` subtitle, a dead "go to artist"
link) or as duplicate rows for one song, and running the audit checklist in §8.0d
over the codebase found a fourth (#28) — an unguarded `firstWhere` that would have
thrown `StateError: No element` from a playlist sheet.

**Pass 5 is the second run on hardware** (§5.6), this time with the user
reporting what they saw rather than what the log said. Its lesson is the opposite
of pass 4's: all three symptoms were *architectural*, not typed — a route pushed
at the wrong level of the tree, a whole-file audio engine asked to feel like a
streaming one, and a storage layer whose failures were invisible by construction.
Nothing in `flutter analyze` could have found any of them, and only the first was
a crash waiting to happen.

### 5.1 Pass 2 — the complete list

| # | Location | Analyzer message | Root cause | Fix |
| --- | --- | --- | --- | --- |
| 1 | `core/theme/app_theme.dart:137` | `CupertinoPageTransitionsBuilder` isn't defined / invalid constant / non-constant map value | This Flutter (3.47.7) no longer exports `CupertinoPageTransitionsBuilder` from material; only `FadeForwardsPageTransitionsBuilder` and `ZoomPageTransitionsBuilder` exist | Both platforms now use `const FadeForwardsPageTransitionsBuilder()` |
| 2 | `core/theme/swiss_error_card.dart:1` | unnecessary `foundation.dart` import | `material.dart` re-exports everything used (`FlutterErrorDetails`) | Import deleted |
| 3 | `core/theme/swiss_error_card.dart:135` | property `keycapTop` can't be accessed in a constant expression | A `const` object's *field access* is not a compile-time constant in Dart — `const LinearGradient(colors: [t.keycapTop, …])` can never work | Dropped `const` from that `LinearGradient` (the tokens are still `const`) |
| 4 | `core/theme/tactile_decorations.dart:285` | argument type `TextStyle` can't be assigned to `String?` | `fontFamily:` takes a family **name**; `SwissType.mono` is a whole `TextStyle` | `fontFamily: SwissType.monoFont` |
| 5 | `main.dart:4` | unnecessary `foundation.dart` import | `debugPrint` also comes via material | Import deleted |
| 6 | `presentation/navigation.dart:5,6,7` | target of URI doesn't exist | Paths were written as if the file lived in `lib/` (`../screens/…` = `lib/screens/…`). It lives in `lib/presentation/`, so the prefix was one level too many | `../screens/…` → `screens/…` |
| 7 | `navigation.dart:17,43,52` | `NowPlayingScreen` isn't a class, `CollectionDetailScreen`/`PlaylistDetailScreen` undefined | Pure fallout from #6 | Resolved by #6 |
| 8 | 20 call sites (see below) | named parameter `hapticOnPress` isn't defined | `TactileIconKeycap` never exposed `hapticOnPress`, although `TactileKeycap` did — every sheet header tried to pass it | Added `hapticOnPress = true` to `TactileIconKeycap` and forwarded it to the inner `TactileKeycap`. **One widget fix instead of 20 call-site edits.** |
| 9 | `screens/collection/collection_detail_screen.dart:453` | unused local `t` | A `SwissTokens.of(sheetContext)` binding that the sheet never used | Line deleted |
| 10 | `screens/library/library_screen.dart:10` | unused import `service_locator.dart` | Left over from an earlier layout | Import deleted |
| 11 | `screens/library/library_screen.dart:227` | method `_open` isn't defined for `_LibraryGrid` | `_open` and `_playlistOptions` were `static` members of the **sibling** widget `_LibraryRow`; Dart does not resolve those unqualified from another class | Promoted both to **top-level** functions in the same library, so the grid and the row list share one routing rule |
| 12 | `screens/library/playlist_detail_screen.dart:380–415` | undefined name `tracks` (7 uses) | `_options(context)` is a method of `_PlaylistView`, but `tracks` was a local inside `build()` | `_options(BuildContext, List<Track> tracks)`; the caller passes `tracks` |
| 13 | `screens/now_playing/now_playing_screen.dart:325,330,331` | no constant `one` / `off` in `RepeatMode` | Flutter **now exports its own `RepeatMode`** (`repeating_animation_builder.dart`) through material, and it shadowed ours from `services/settings_service.dart`; the screen didn't import settings_service at all | `import '../../../services/settings_service.dart';` **plus** `import 'package:flutter/material.dart' hide RepeatMode;` |
| 14 | `screens/now_playing/now_playing_screen.dart:426–428` | undefined `VisualizerMode` | Same missing import as #13 (`VisualizerMode` also lives in `settings_service.dart`) | Fixed by #13's import |
| 15 | `screens/now_playing/queue_bottom_sheet.dart:134,139,140` | `RepeatMode` is ambiguous (material vs settings_service) | This file already imported both | `import 'package:flutter/material.dart' hide RepeatMode;` |
| 16 | `screens/now_playing/queue_bottom_sheet.dart:75` | `onReorder` is deprecated (after v3.41) | `ReorderableListView` replaced it with `onReorderItem`, which reports the **already-adjusted** final index | Switched to `onReorderItem` and removed the old manual `newIndex - 1` fix-up — which also matches `PlaybackService.reorderQueue(old, new)` exactly (it removes, then inserts at `new`) |
| 17 | `widgets/fft_visualizer.dart:155,194` | undefined class `ValueListenable` | In this Flutter, `material.dart` does **not** re-export `ValueListenable` | Added `import 'package:flutter/foundation.dart';` — then the analyzer reported `dart:typed_data` as unnecessary (`Uint8List`/`Float32List` come from foundation), so that import was removed too |
| 18 | `shell/main_shell_screen.dart:5`, `widgets/screen_header.dart:4` | unused import `tactile_decorations.dart` | Both stopped using the kit directly | Imports deleted |
| 19 | `widgets/track_options_sheet.dart:9` | unused import `service_locator.dart` | Left over | Import deleted |
| 20 | `widgets/track_options_sheet.dart:263` | optional parameter `tag` is never given | `_SheetHeader` had one call site, which used the default | Parameter removed; the string is inline again |
| 21 | `test/widget_test.dart:16` | `MyApp` isn't a class | Untouched `flutter create` template test | Replaced with 5 real tests (see §7) |
| 22 | `android/app/src/main/AndroidManifest.xml` | **`Build failed due to use of deleted Android v1 embedding.`** (build-time only — `flutter analyze` cannot see it) | The manifest was rewritten for `audio_service` + Impeller and the **`flutterEmbedding` marker got dropped**. Before every Android build, Flutter parses the app manifest (`flutter_tools/lib/src/project.dart` → `computeEmbeddingVersion()`) and classifies the app as v1 unless it finds `<meta-data android:name="flutterEmbedding" android:value="2"/>`, then aborts with `exitCode 1` **before Gradle even starts** | Restored the marker inside `<application>` with a "DO NOT DELETE" comment |
| 23 | `android/app/build.gradle.kts` (default's `ndk { abiFilters … }`) | `Conflicting configuration : 'armeabi-v7a,arm64-v8a' in ndk abiFilters cannot be present when splits abi filters are set : armeabi-v7a,x86_64,arm64-v8a` | AGP forbids `ndk.abiFilters` and `splits.abi` at the same time. `--split-per-abi` makes the Flutter Gradle plugin enable `splits.abi` (`reset()` + `isUniversalApk = false`), so our ARM-only `abiFilters` became illegal. Worse, the two mechanisms fight: without splits the plugin *clears* `abiFilters` and replaces them with **all three** of its platforms (arm, arm64, **x64**), so a plain build would package x86_64 libraries from third-party plugins | Removed `ndk.abiFilters` entirely and enforced ARM at **packaging** time instead: `packaging { jniLibs { excludes += listOf("lib/x86/**", "lib/x86_64/**") } }`. Packaging filters run after variant configuration, cannot be reset by the plugin and cannot conflict with splits. Builds pass `--target-platform android-arm --target-platform android-arm64` so no x86_64 snapshot is compiled either |

### 5.2 Where the `hapticOnPress` errors were

`add_to_playlist_sheet.dart:59`, `eight_d_calibration_sheet.dart:42`,
`import_url_sheet.dart:77`, `track_options_sheet.dart:309`,
`track_list_tile.dart:154`, `collection_detail_screen.dart:465,516`,
`library_screen.dart:311,394`, `playlist_detail_screen.dart:252,291,385`,
`lyrics_bottom_sheet.dart:122`, `now_playing_screen.dart`, `queue_bottom_sheet.dart:57,245,254`,
`sleep_timer_sheet.dart:56`, `search_screen.dart:187,372`, `settings_screen.dart:494`.

### 5.3 Auxiliary changes made during the same pass

* `dart format` was run over the touched files, so the moved functions in
  `library_screen.dart` are indented like top-level code.
* `flutter pub get` synced `pubspec.lock` and **dropped `google_fonts 9.0.0`** from
  the lock — the fonts are bundled as assets in `assets/fonts/` and declared in
  `pubspec.yaml`, so the package was already unused. If you ever see
  `Changed 1 dependency!` on a cold machine, that is this.

### 5.4 Pass 4 — the first device run, plus what the new tests and the audit found

| # | Where | What the user saw | Root cause | Fix |
| --- | --- | --- | --- | --- |
| 24 | `presentation/screens/home/home_screen.dart` → `_Body._sections()` | The fault card: `type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of 'child'`, `LIBRARY: widgets library`, stack through `_ViewportElement.insertRenderObjectChild` → `ContainerRenderObjectMixin.insert` | `_sections()` returns the list that `_Body` spreads into **`CustomScrollView.slivers`**, and it returned **box** widgets there: `SwissRail` builds a `Column` (a `RenderConstrainedBox` appears via its children/wrappers), and the empty-rail branch returned a bare `SizedBox.shrink()`. A viewport's children must be slivers, and a `RenderSliver` cast is enforced at insert time | Added **`SliverRail`** to `presentation/widgets/collection_cards.dart` — the same rail with a sliver-shaped API (`SliverToBoxAdapter` around `SwissRail`, and a `SliverToBoxAdapter` for the empty case). Home now builds rails through `SliverRail` |
| 25 | `data/datasources/jiosaavn_client.dart` → `_parseCollectionLike()` | Nothing visible yet — found while writing the Law 7 tests | `Fmt.cleanTitle('')` answers with the **`'Unknown'` sentinel**, so `final music = Fmt.cleanTitle(_str(more['music']))` was never empty and the `music.isEmpty ? 'ALBUM' : 'PLAYLIST'` fallback was **dead code**: an album row with no music line would have shown `UNKNOWN` instead of `ALBUM` | Normalised the sentinel back to `''` before the check (`musicLine == 'Unknown' ? '' : musicLine`), so the fallback actually runs |
| 26 | `data/datasources/jiosaavn_client.dart` → `_parseSong()` | Nothing visible yet — found by a test that fed a blank artist name | `artistId: primaries.isEmpty ? null : _str(primaries.first['id'])` produced `''` for an entry with no id, so the model's nullable `artistId` was "not null but empty". Callers guard with `artistId != null` to decide whether "go to artist" is offered, so an empty id would send the user to a broken artist page | Same `isEmpty → null` guard `albumId` already had |
| 27 | `data/models/track.dart` → `Track.dedupeKey` | Duplicate queue/history rows for one recording | The doc comment promised that `(From "…")` suffixes were folded away before comparing, but nothing anywhere in `lib/` strips them: a search row (`Kesariya`) and an album row (`Kesariya (From "Brahmastra")`) produced different keys, so `dedupe()` kept both | The parenthetical group is now stripped (`[(\[…from…)\]]`, case-insensitive) with a guard so a title that *is* only a parenthetical cannot normalise to nothing |
| 28 | `presentation/screens/library/library_screen.dart` → `_playlistOptions()` → **DOWNLOAD EVERY TRACK** | Would have been `StateError: No element` (a fault card, or a silent dead row) | `library.state.playlists.firstWhere((p) => p.id == id)` had **no `orElse`**. The sheet is a live view of mutable state: the playlist can vanish between opening it and tapping (deleted, re-imported, state reload) | Replaced with a `where(...)` + `isEmpty` guard that returns quietly — the list behind the sheet already reflects the deletion. Found by the audit checklist in §8.0d, not by a user |

**Why `flutter analyze` never saw it:** `slivers:` is typed `List<Widget>`, so a
box widget type-checks fine and only explodes when the viewport inserts its render
object — i.e. at **first paint**. It is the Dart equivalent of a missing sliver
adapter.

**Why it was not caught earlier:** the Home feed had never rendered before. There
was no Android device during development, and the one desktop run was stopped on
request before the first frame.

**The rule, now encoded in the code:** *slivers list → `SliverRail`; box list →
`SwissRail`.* Both are regression-tested (`test/widget_test.dart`, "SliverRail is a
real sliver — empty and populated"): the test pumps a `CustomScrollView` with an
empty and a populated rail inside, so if `SliverRail` ever stops being a sliver the
test fails with the very same exception the device threw.

**Prevention, not just repair:** the same reasoning produced §8.0d, a checklist of
the six fault families `flutter analyze` is blind to (box-in-slivers, unbounded
horizontal lists, `firstWhere` without `orElse`, `.first`/`[0]` on empty
collections, null assertions, shared `ScrollController`s), each with the `grep`
that finds it. Run it before the next device run rather than after.

Also fixed as part of the same pass: two `if (…) return …;` statements that
`dart format` wrapped onto two lines, which arms `curly_braces_in_flow_control_structures`
— both now use braces.

**Law 7 became testable in the same pass.** The JioSaavn payload coercers were
private, so hostile-payload behaviour could only be checked by hand. Five
`@visibleForTesting` seams were added (`parseSong`, `parseRailItem`,
`parseCollection`, `rememberedEncrypted` and the now-public statics
`decryptMediaUrl` / `rewriteBitrate`) — one line each, no logic — and
`test/jiosaavn_parsing_test.dart` (28 cases) now pins down: id-less songs being
dropped, every optional field missing at once, numbers-as-strings, `'false'`/0/1
flags, HTML entities and numeric entities, artist-map → subtitle → sentinel
fallback, thumbnail → 500×500 artwork, the encrypted-URL cache hand-off, the
rail union's kind mapping, collection counts from all three fields, `perma_url`
token extraction, the **real DES fixture** (`tool/des_check.dart`, including the
`-`/`_` url-safe alphabet) and the `_96 → _320` rendition rewrite, plus
`Track.fromMap`/`listFrom` on rotten persisted maps and a lossless
`toMap → fromMap` round trip. That pass ended with **34 tests** across two files;
pass 5 added `test/streaming_test.dart` and two chassis tests for **46** (§7).

### 5.5 Two of the new tests failed first — the payload shape, not the code

Worth recording, because it documents the real JioSaavn object shape:

| Test | First failure | The truth |
| --- | --- | --- |
| `parseCollection … counts` | Expected `14` from `more_info.list_count` | `song_count` lives **inside `more_info`**, while `list_count` and `count` are **top-level** fields of the same object. The parser already read all three correctly — my test payload was impossible. Both shapes are now asserted. |
| `parseSong … artists` | Expected `artistId == null` for a blank artist name | The fixture entry was `{'id': 1, 'name': '   '}`: a blank *name* still carries a real id, so `artistId: '1'` is correct. The sentinel path is covered by an entry with no id at all. |

Lesson: when a hostile-payload test fails, check whether the payload could even
exist before touching the parser. Neither of these was a product bug — the two
*real* defects in this pass (#25, #26) failed for genuine reasons.

### 5.6 Pass 5 — the second device session: the three symptoms the user reported

Reported verbatim: *"when i click any song it is buffering at starting and take
about 10 to 15 sec before playing"*, *"in like in home i go to any playlist and
click any song the song playing at bottom dosent show"*, *"like dosent work"*.

| # | Where | What the user saw | Root cause | Fix |
| --- | --- | --- | --- | --- |
| 29 | `presentation/shell/main_shell_screen.dart`, `presentation/navigation.dart` | A song started from a playlist played **with no mini-player at the bottom** | The transport dock and the tab bar *are* the shell `Scaffold`'s `bottomNavigationBar`, so they exist only while the shell's own route is the topmost one. `openCollection` / `openUserPlaylist` pushed on the **root navigator**, so opening a playlist buried the dock under the detail route: the song was playing, but nothing on screen said so | The chassis now owns a **nested `Navigator`** (`NavigatorPopHandler<void>` keeps Android's back button working; a tab tap does `popUntil(isFirst)`). Every detail route lands inside it, so the dock + tab bar survive browsing into albums, playlists and artists. `openNowPlaying` is the deliberate exception — it now pushes with `rootNavigator: true`, so the full-screen player still covers the chassis. Table rule: **browse → nearest navigator, play → root navigator** |
| 30 | `services/media_cache.dart`, `data/repositories/music_repository.dart`, `presentation/widgets/track_prefetch.dart` (new) | `BUFFERING` for 10–15 s on every first play | Three compounding causes. (a) `flutter_soloud` **cannot stream** an MP4/M4A container — its own `LoadMode` docs say platform-decoded formats are "fully decoded to PCM in memory when loaded" — so time-to-first-sample is always *whole download + decode*, and a 320 kbps JioSaavn file is ~10 MB. (b) That download ran over a **single TCP connection** on a CDN that throttles one socket well below the phone's bandwidth. (c) A delisted rendition answers `200` with an HTML/JSON error page, which the old code stored as if it were audio: SoLoud then failed to decode it, the ladder moved to the next rung, and seconds vanished | ✅ **`MediaCache` now transfers over 4 ranged lanes** (`Range: bytes=a-b`, one file per lane, concatenated in order) after a one-byte probe that also reports the real length; `Range` refusal or any lane failure falls back to the original single-stream path, unchanged. ✅ **Error pages are rejected before storage** — by `Content-Type` and, with the final word, by the container's magic bytes (`ftyp`/`ID3`/frame-sync/`OggS`/`fLaC`/`RIFF`). ✅ **`MusicRepository.prefetchTracks()`** warms the first one or two entries of a list the moment it opens, through the new `TrackPrefetch` wrapper on the collection and playlist screens, so the tap that follows usually hits the disk |
| 31 | `data/sources/local_store.dart`, `presentation/cubits/library_cubit.dart`, `now_playing_screen.dart`, `track_options_sheet.dart`, `data/repositories/library_repository.dart` | "like dosent work" — the heart did nothing | Two independent paths made the button look dead. (a) Every read and write went through `_liked?.get/put(...)`: a box that failed to open turned a like into a **silent no-op** — no error, no state change, `readLiked()` returns `[]`, so neither the heart nor Liked Songs ever changed. (b) The heart called `PlayerCubit.toggleLike`, which has no toast channel, and the `⋮` sheet closed with no feedback either — so even a like that *saved* looked like it did nothing | ✅ Storage writes go through `_writeBox`, which mirrors the value in memory first, so a missing or failing box can no longer swallow a like (and `LocalStore.diagnostics()`/`storageWarning` now say `STORAGE: DEGRADED` in `COPY REPORT` — wired through `SwissErrorCard.reportExtra` from `main.dart`). ✅ A box that refuses to open is reset once (`deleteBoxFromDisk` + reopen) instead of switching the whole Library off. ✅ Both like entry points now go through `LibraryCubit.toggleLike`, which toasts `ADDED TO`/`REMOVED FROM LIKED SONGS` and, if storage is degraded, says `ONLY FOR THIS SESSION // LOCAL STORAGE UNAVAILABLE` once |

Two smaller things came out of the same audit:

* **`MusicRepository.renditionLadder()`** — the ladder used to try the 320 rung
  even for a track the catalogue had already flagged `has320: false`: a failed
  fetch and a wasted round trip per track, on the products of a slow connection.
  It is now a pure, tested function.
* **`LibraryRepository.isLiked()`** — the player asks this on every 250 ms
  position tick, and it used to decode *every* liked track's map each time. The
  id set is now cached and rebuilt only when the store's revision changes.

**The rule for the mini-player, in one line:** *the bottom chrome belongs to the
shell's route; if something must stay visible above a pushed screen, the push has
to happen inside the shell.* Both halves of that are locked down by tests
(`test/widget_test.dart`, "a detail screen pushed inside the chassis keeps the
dock" and its falsification twin "a root push is what used to bury the dock").

**Escape hatch for the next device report:** `flutter_soloud` needs the *whole*
file before it can decode an M4A, so a "instant start" that beats the network was
never available inside this engine. If 4 lanes + prefetch still feel slow on a
device, the remaining levers are (in order of cost): start at 160 kbps for the
first play and warm 320 in the background, or write an ADTS/AAC buffer-stream
source for `flutter_soloud`'s `setPullBufferStream` API. Both are recorded in
§10 rather than guessed at now.

> **Update — pass 6 (§5.7): the second lever was pulled.** The user re-reported
> the same latency, so the ADTS buffer-stream source was written: Musify now
> demuxes the MP4 itself (`services/mp4_aac.dart`) and feeds AAC frames to
> `setPullBufferStream` while a single re-positionable transfer is still running.
> The 4-lane transfer and prefetch are unchanged and remain the fallback.

---

### 5.7 Pass 6 — the third device session: **instant playback**, and the four UI complaints

Reported verbatim: *"STILL bro it take some time to start playing song after i
click it i want instant play of any song"*, *"still which i click like button in
song player it dont add it to liked playlist"*, *"the important function dont
work it scan all the song but it dont add a playlist of that or give option to
add those song in which playlist"*, *"remove the number from the bottom nav
bar"*, *"the top suggestion dont work in home page like all music 8d spatial
pick and offline ready"*.

| # | Where | What the user saw | Root cause | Fix |
| --- | --- | --- | --- | --- |
| 32 | `services/mp4_aac.dart` **(new)**, `services/media_cache.dart`, `services/player/playback_service.dart`, `data/repositories/music_repository.dart` | "It takes some time to start playing" — still, after pass 5's four-lane transfer | `flutter_soloud` cannot decode an M4A container incrementally: `loadFile`/`loadUrl` **fully decode to PCM on load**, so the shortest possible wait is *whole download + whole decode*, and a 320 kbps file is ~10 MB. No amount of transfer tuning removes that floor. The engine *does* have one streaming API — `setPullBufferStream` — but it only accepts raw elementary streams (ADTS AAC, MP3, Ogg, FLAC), not MP4 | ✅ **Musify's own MP4 → ADTS demuxer.** `mp4_aac.dart` parses `moov`/`stbl` (`stsd`→`esds`→AudioSpecificConfig, `stsz`, `stsc`, `stco`/`co64`, `stts`) and reports every sample's file offset, size and ADTS offset, then wraps frames in ADTS headers on the way into the engine — and a rendition that is **not** an MP4 (the older `_96.mp3` rungs, or a file already in the vault that the engine decodes natively) skips all of that and streams its bytes **raw**, so "instant play" does not depend on the container. ✅ **`MediaCache.openStream()`** — a read-while-writing transfer: one sequential GET, bytes written at their real file offsets through a repositionable cursor (`ByteCoverage` merges downloaded ranges and says where the first hole is), reads served as soon as their range has landed, connection reopened when a seek jumps more than 512 KB ahead. ✅ **`PlaybackService._startProgressive()`** feeds `onMoreDataIsNeeded` ~190 KB windows out of it, so the first sample is audible in the time it takes to fetch the header + a few frames. ✅ The finished file is renamed into the cache exactly as `ensure()` would have, so the *next* play is a plain disk read. ✅ **Every failure is a fallback, never an error**: no length header, no usable sample table (an MP4 the demuxer refuses, an `ftyp` file with an unreadable table), a fragmented MP4, a transfer that produces no sound within 7 s → the old download-then-load route runs instead (and that track is not retried in a loop). ✅ Tunable in Settings ▸ 04 PLAYBACK BEHAVIOUR → **INSTANT PLAY** (default on: "STREAM FRAMES — SOUND IN UNDER A SECOND" / off: "DOWNLOAD FIRST — SLOW TO START, SAFEST") |
| 33 | `presentation/screens/now_playing/now_playing_screen.dart`, `presentation/cubits/library_cubit.dart` | *"when i click like button in song player it dont add it to liked playlist"* | The full-screen player's heart read and wrote a **different source of truth** than the one the Liked Songs screen and the `⋮` sheet used (`PlayerCubit.isLiked` vs. `LibraryCubit.likedList`). Two views of one fact is one view too many: they could — and did — disagree | The heart is now a `BlocSelector<LibraryCubit, LibraryState, bool>` over `library.liked.any((t) => t.id == track.id)` — the *same* list the ⋮ sheet toggles and the Liked Songs screen renders, so it cannot disagree with either. `LibraryCubit.toggleLike` also verifies by **reading the store back** after the write and says so in the toast if the write did not land (`ONLY FOR THIS SESSION // LOCAL STORAGE UNAVAILABLE`) |
| 34 | `presentation/cubits/library_cubit.dart`, playlist importer sheet | *"it scan all the song but it dont add a playlist of that or give option to add those song in which playlist"* | The importer scanned a `.m3u`/`.json`/`.txt` file, matched every song — and then filed the result **nowhere**: it waited for a "current playlist" that no longer existed in the new Library flow, so the matches were dropped on the floor | The scan now parks a **`PendingImport`** and opens a sheet that asks the question the user was asking: **CREATE PLAYLIST** (named after the file, editable) or **ADD TO EXISTING** (the library's own playlists). Nothing is written until the question is answered, and the sheet shows how many of the scanned tracks actually matched |
| 35 | `presentation/shell/main_shell_screen.dart` | *"remove the number from the bottom nav bar"* | The tab bar rendered a design-system ordinal (`01…04`) above each icon — chassis decoration from the mock, not navigation | Ordinals removed; label + icon only. The `RailItem`/`_NavItem` model no longer carries an index for display |
| 36 | `presentation/screens/home/home_screen.dart`, `presentation/cubits/home_cubit.dart` | *"the top suggestion dont work in home page like all music 8d spatial pick and offline ready"* | The three pills were *decorative* — they rendered as buttons and did nothing when tapped (no route, no filter, no scroll) | Each pill now owns a **scoped landing view** it scrolls to and highlights: **ALL MUSIC** → the catalogue rail (genres/moods), **8D SPATIAL** → the spatial rail plus the ARM 8D switch, **OFFLINE READY** → the downloads/cache section with a real empty state ("nothing downloaded yet" + the CACHE meter) instead of a blank rail |

**How instant play actually works (the one-paragraph version, for the next
person):** JioSaavn's 320 kbps files are progressive MP4s whose `moov` sits
before `mdat`, so the sample table is in the first ~47 KB. `Mp4AacIndex.parse`
reads that table out of a 96 KB head request; `windowAt(offset, 190 KB)` turns an
ADTS byte offset into a *file* range aligned to frame boundaries;
`MediaCache.openStream` is already downloading the file sequentially in the
background; `assemble` wraps the frames in ADTS headers; `addPullBufferDataStream`
hands them to SoLoud at their exact ADTS offset. Seeks move the *engine's* read
head, which moves the transfer's cursor, which is why a seek is a rebuffer of a
few hundred milliseconds rather than a restart. `tool/adts_check.dart` proves the
whole chain against a live file without a device (it re-fetched a real 320 kbps
"Kesariya": 11,550 samples, `4m28s`, alignment exact, 0 bad frames).

**Build marker (so the next report can name the APK):** Settings ▸ ABOUT and the
first line of `COPY REPORT` now carry `kBuildLabel` (`1.0.2+3 · STREAM-ENGINE ·
2026-10-17`, `lib/core/build_info.dart`). A report that does not start with that
line came from an older APK, which is the first thing to check.

**Two bugs the new tests caught before the device did** — recorded because neither
would ever have looked like an error on a phone, only like "it still stutters":

1. **`ByteCoverage.add` lost the tail of a merged range.** The first version built
   the merged list *while* walking, so a range that bridged two existing runs
   (`…add(5, 25)` over `[0,10)` and `[20,30)`) absorbed the second run but left the
   tuple it had already written at `[0,25)`. Effect on a device: after a seek
   forward and back, the coverage arithmetic would under-report by exactly the
   bridged amount, so a completely downloaded file could never be recognised as
   complete — it would be re-fetched forever and never renamed into the cache.
   Fix: insert the new range in order, then sweep the list once and *widen the run
   in place*. Pinned by three tests in `test/mp4_aac_test.dart`
   ("tracks holes…", "absorbs an overlapping range…", "an empty range changes
   nothing") plus the seek test in `test/media_cache_stream_test.dart`.
2. **A feed that failed *because* the voice was torn down could trigger a spurious
   fallback.** `_feedFrames` awaited a session read, and if `_teardownVoice` ran
   while that read was in flight the read returned `null` — which the old order
   treated as "the stream broke", counted a stumble, and (at three) called
   `_fallBackFromStream`, tearing down the voice that had *just started* and
   reloading the track. Effect on a device: an occasional double-start or a
   restart at every track change. Fix: check `_disposed || !_streaming` **before**
   blaming the bytes, and make `_fallBackFromStream` verify it is still being
   called for the track that is playing.

---

## 6. Decisions & deviations (so nobody re-litigates them by accident)

| Decision | Why |
| --- | --- |
| **YouTube fallback removed** (the one PRD deviation) | `saavn.dev` is dead, public Piped instances returned 525/502, and `youtube_explode_dart` could search but never extract a stream (`VideoUnplayableException` — YouTube now requires PO-token/botguard attestation that a plain Dart client cannot satisfy without a paid key, which the PRD forbids). The waterfall became JioSaavn 320 → 160 → 96 → direct URL → on-disk copy. Documented in `README.md` and in Settings ▸ About. |
| Media-URL decryption uses `DESedeEngine` with the 8-byte key repeated 3× | `pointycastle 4.0.0` has no single-DES engine. Triple-DES with a repeated key is byte-identical to DES-ECB. Proven by `tool/des_check.dart`. |
| `MediaCache` owns every byte on disk | `flutter_soloud.loadUrl` downloads the whole file before playing anyway, so the cache gives us real progress, instant replays, prefetch, crossfade and offline in one place. |
| Fonts bundled, not `google_fonts` | Identical typography with zero network and no runtime font fetching. |
| `PlaybackService` is platform-free; `audio_service` only attaches on mobile | Lets the engine be driven directly (and unit-tested) without a media session; `AudioService.init` runs only when `isMobilePlatform`. |
| 8D orbit driven by `Timer.periodic(16ms)` in Dart | Survives backgrounding and does not depend on a Flutter ticker being on screen. |
| EQ = SoLoud parametric EQ, `bandGain(i).value` 0–4 with `1.0` neutral | Centres `[31, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k]`, Q = 1.0; bass boost 0–4. |
| Backup import = paste JSON, export = `SharePlus.instance.share(ShareParams(...))` | Avoids a `file_picker` dependency that the PRD does not require. |
| Playlist import reads YouTube/Spotify pages for **metadata only** and re-matches on JioSaavn | Nothing is scraped from a protected source; the import produces playable JioSaavn tracks. |
| `LibraryCubit` is an app-wide singleton | Three surfaces (library screen, track sheet, playlist editor) read the same instance; a factory per-screen would fork the state. |

---

## 7. Verification evidence

```
$ flutter analyze --no-pub
No issues found! (ran in 55.7s)            # final pass-6 run

$ flutter test
00:00 +0: loading test/jiosaavn_parsing_test.dart
...
00:03 +56: rendition ladder walks 320 → 160 → 96 for a track that has them
00:04 +67: a detail screen pushed inside the chassis keeps the dock
00:04 +68: a root push is what used to bury the dock
00:04 +69: SliverRail is a real sliver — empty and populated
00:06 +69: All tests passed!
```

Five test files, no device, no network, no audio engine:

| File | Cases | What it locks down |
| --- | --- | --- |
| `test/widget_test.dart` | 8 | `Fmt` playhead/size/count formatting, HTML cleaning, both chassis token sets, `TactileKeycap`/`TactileIconKeycap` behaviour (`Haptics.enabled` is switched off in `setUp` so no platform channel is touched), **`SliverRail` really being a sliver** (§5.4 #24) and **the chassis keeping its dock across a pushed detail screen** (§5.6 #29, both directions: the nested push keeps it, a root push buries it) |
| `test/jiosaavn_parsing_test.dart` | 28 | **Law 7**: hostile JioSaavn payloads (missing keys, nulls, `'217'` durations, `'false'`/`0`/`1` flags, HTML + numeric entities, empty artist maps), the rail union's kind mapping, collection counts/tokens, the real DES fixture plus the url-safe alphabet, `_96 → _320` and thumbnail → 500×500 rewriting; **Law 8**: rotten `Hive` maps in `Track.fromMap`/`listFrom` and a lossless `toMap → fromMap` round trip |
| `test/streaming_test.dart` | 10 | **the pass-5 fixes**, all pure: container sniffing (`ftyp`/`ID3`/frame-sync/`OggS`/`fLaC`/`RIFF`) and error-page rejection by content type *and* magic bytes, range splitting (contiguous, non-overlapping, covers the file, small files stay one lane), the rendition ladder skipping `has320: false`, and **a `LocalStore` with no open boxes still round-tripping likes, downloads, history, searches and recent collections** — the "silent no-op" that made a heart look dead |
| `test/mp4_aac_test.dart` | 17 | **the pass-6 demuxer, byte-exact against a hand-built MP4** (three chunks, six samples, known sizes): the `stsd`/`esds` walk to the AudioSpecificConfig, duration from `stts`, every sample's absolute file offset from `stco`/`stsc`, frame windows that start and end on frame boundaries, the canonical 7-byte ADTS header (`FF F1 50 80 0D 7F FC` for a 100-byte 44.1 kHz stereo frame) and mono/other-rate headers, byte-for-byte `assemble`, the short-read refusal, the whole-stream walk, `parseAnywhere` over a tail `moov`, and the four rejections (truncated `moov`, fragmented `moof`, past-EOF table, zero samples). Plus **`ByteCoverage`**: holes, neighbour merging, overlap absorption and the empty range that must change nothing |
| `test/media_cache_stream_test.dart` | 6 | **the pass-6 transfer**: a staged cache entry is served with **no network at all** (the replay path), reads are exact at any offset, `overFile` refuses missing/empty files, `ensure` short-circuits for an already-staged file, an unreachable URL yields `null` instead of throwing (the fallback contract), and a forward seek leaves a hole that a later fetch fills without double counting |

### 7.1 Release APK — proven, not assumed

```
$ flutter build apk --release --target-platform android-arm --target-platform android-arm64
Running Gradle task 'assembleRelease'...                         1020.8s   # cold
√ Built build\app\outputs\flutter-apk\app-release.apk (43.0MB)
# after the pass-4 fixes: 222.7s (incremental), same 43.0MB
# after the pass-5 fixes: 192.3s (incremental), 43.0MB / 45,117,803 bytes
#   ABIs re-read from the zip: arm64-v8a + armeabi-v7a, 22 native libs,
#   zero x86 entries, libflutter_soloud_plugin.so present in both
# after the pass-6 fixes: 135.3s (incremental), 43.3MB / 45,363,567 bytes
#   mtime 2026-10-17 17:27:34 — later than the newest lib/ source (17:23:16)

$ aapt2 dump badging app-release.apk
package: name='com.musify.musify' versionCode='3' versionName='1.0.2'
         compileSdkVersion='36'
minSdkVersion:'26'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.FOREGROUND_SERVICE'
uses-permission: name='android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
launchable-activity: name='com.musify.musify.MainActivity'
native-code: 'arm64-v8a' 'armeabi-v7a'

# zip inspection of the payload — 22 native libraries, zero x86 entries:
lib/arm64-v8a/   libapp.so  libflutter.so  libflutter_soloud_plugin.so
                 libdartjni.so  libFLAC.so  libogg.so  libopus.so
                 libvorbis.so  libvorbisenc.so  libvorbisfile.so
                 libdatastore_shared_counter.so
lib/armeabi-v7a/ (same set)
lib/x86/*        none
lib/x86_64/*     none
```

That is the PRD's ABI requirement (arm64-v8a + armeabi-v7a), the PRD's API window
(minSdk 26 → targetSdk 36), and the proof that the audio engine actually shipped —
all read out of the built artifact rather than inferred from config.

**Freshness check** (so nobody tests a stale artifact — it has caught us once):

```powershell
Get-Item build\app\outputs\flutter-apk\app-release.apk | Select-Object LastWriteTime
Get-Item lib\presentation\screens\home\home_screen.dart, lib\data\models\track.dart |
  Select-Object Name, LastWriteTime
```

The APK's timestamp must be **later** than the newest source file you changed.
After pass 4: APK `10/17/2026 15:37:04` vs newest `lib/` source
`library_screen.dart` `10/17/2026 15:29:51` → `True`. After pass 5: APK
`10/17/2026 16:15:11` vs newest `lib/` source `library_cubit.dart`
`10/17/2026 16:05:27` → `True`. After pass 6: APK `10/17/2026 17:27:34`
(45,363,567 bytes) vs newest `lib/` source `playback_service.dart`
`10/17/2026 17:23:16` → `True` (this one-liner does it for the whole tree):
`Get-ChildItem lib -Recurse -Filter *.dart | Sort-Object LastWriteTime -Descending | Select-Object -First 1`.
This check exists because a build started *before* an edit finishes *with* the old
code, and nothing in the build log says so — pass 6 hit it twice (a teardown-race
fix and the raw-stream path both landed mid-build), which is why the final artifact
was built *after* the last edit rather than trusting the previous success.

---

## 8. Troubleshooting index — symptom → cause → action

### 8.0 `Build failed due to use of deleted Android v1 embedding.`

**Cause:** `android/app/src/main/AndroidManifest.xml` lost the v2 marker. The
Flutter tool parses the app manifest before Gradle runs and aborts unless it finds
`<meta-data android:name="flutterEmbedding" android:value="2"/>` inside
`<application>`. Nothing to do with `MainActivity` in this case — the class still
extends `AudioServiceActivity` (v2), but the tool never gets that far.
**Action:** keep that meta-data. It is annotated `DO NOT DELETE` in the manifest.
Note this failure is invisible to `flutter analyze` — only `flutter build` and
`flutter run` surface it.

### 8.0b `Conflicting configuration : 'armeabi-v7a,arm64-v8a' in ndk abiFilters cannot be present when splits abi filters are set`

**Cause:** two ways to restrict ABIs exist in AGP, and they are mutually exclusive:
`defaultConfig.ndk.abiFilters` and `splits.abi`. `--split-per-abi` makes Flutter's
Gradle plugin turn on splits, so the project's own `abiFilters` becomes illegal.
Dropping `abiFilters` alone is not enough either: **without** splits the Flutter
plugin clears `abiFilters` and re-fills them with arm + arm64 + **x86_64**, so a
plain build silently gains x86_64 payload.
**Action:** never set `ndk.abiFilters` in this project. ARM-only is enforced in
`android/app/build.gradle.kts` by a `packaging { jniLibs { excludes +=
listOf("lib/x86/**", "lib/x86_64/**") } }` block (packaging filters run after
variant configuration, cannot be reset by the plugin, and cannot conflict with
splits), and builds pass `--target-platform android-arm --target-platform
android-arm64`. `--split-per-abi` is deliberately not used — Flutter's plugin
`reset()`s the split includes and an x86_64 split appears.

### 8.0c `type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of 'child'`

**Where it shows up:** the fault card, with `LIBRARY: widgets library` and a stack
through `_ViewportElement.insertRenderObjectChild` / `ContainerRenderObjectMixin.insert`.
**Cause:** a **box** widget was placed in a `slivers:` list (a `CustomScrollView`).
Classic offenders: `SwissRail`, `SizedBox`, `Column`, `Padding` — or a conditional
that returns an empty-state box (`SizedBox.shrink()`) where its siblings are slivers.
`_ViewportElement` casts the child's render object to `RenderSliver` at insert time,
so it explodes on the first paint, not at compile time.
**Action:**
1. `grep -rn "slivers:" lib` — every project has one or two files to check.
2. In a slivers list, wrap boxes: use **`SliverRail`** for rails (`SwissRail` is the
   box version), `SliverToBoxAdapter` for anything else.
3. Make the *empty* branch return a sliver too — `const SliverToBoxAdapter(child: SizedBox.shrink())`
   — because an empty rail can become non-empty on the next rebuild without the
   element being re-created.
4. Run `flutter test`. The test "SliverRail is a real sliver — empty and populated"
   fails with this exact exception if the shape regresses.

### 8.0d Runtime-only faults: the audit checklist

`flutter analyze` cannot see any of these, and they only fire on the device, so
whenever a runtime fault is reported, run this list over the codebase. Provenance
of the pass-4 fixes: **#24** came from the user's first device run, **#28** from
this checklist, **#26/#27** from the Law 7 tests it motivated.

| # | Family | Symptom on device | How to find it |
| --- | --- | --- | --- |
| 1 | **Box widget in a slivers list** | `type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of 'child'` (§8.0c) | `grep -rn "slivers:" lib` — then confirm every entry is a sliver (`SliverRail`, `SliverToBoxAdapter`, `SliverList`…), including the empty branches |
| 2 | **Horizontal list with unbounded height** | `RenderBox was not laid out` / `Vertical viewport was given unbounded height` | `grep -rn "Axis.horizontal" lib` — each needs an ancestor with a fixed height (`SwissRail` uses `height ?? 214`) |
| 3 | **`firstWhere` without `orElse`** | `StateError: No element` — usually after a sheet or dialog pops | `grep -rn "firstWhere(" lib` and check each has `orElse:` or is guarded by a `where(...).isEmpty` |
| 4 | **`.first` / `.last` / `[0]` on possibly-empty collections** | `RangeError` / `Bad state: No element` | `grep -rn "\.first\b\|\.last\b\|\[0\]" lib` — each must be behind an emptiness check or provably non-empty (e.g. a literal list just built) |
| 5 | **Null-assertion on mutable state** | `Null check operator used on a null value` | `grep -rn "\w!\.\|!)\|!;" lib` — each `!` must have a guard in the same expression or the enclosing `if` |
| 6 | **One `ScrollController` on two scrollables** | `ScrollController attached to multiple scroll views` | `grep -rn "ScrollController(" lib` — one controller per view, disposed in `dispose()` |

Pass-4 outcome of this audit: #1 fixed in Home, #3 fixed in the library sheet, and
families 2/4/5/6 came back clean (every hit was already guarded — e.g.
`music_repository`'s `results[0]` comes from `Future.wait` over a literal list of
four futures; `playback_service`'s `_shuffleOrder.first` sits behind the
`repeatMode == all` branch and a length equality check; `_artistCandidates`
always falls back to `['Unknown']`).

### 8.1 "The build seems to hang with no output"
**Cause:** the first build compiles native plugins (`flutter_soloud` → `.so`/`.dll`
via CMake + NDK/MSVC). Console prints nothing for minutes.
**Check it is alive:** look for recently written files under `build/native_assets/`
and `build/app/intermediates/`. If those timestamps keep moving, it is working.
**Don't** kill it and don't run two Flutter builds at once.

### 8.2 The app shows a panel saying `UI FAULT // RECOVERED`

**Cause:** a widget threw; PRD Law 4 replaced the red screen with our card.
**First thing to check for this specific card:** does the exception say
`RenderConstrainedBox` / `RenderSliver`? Then it is §8.0c — a box widget in a
`slivers:` list, and the fix is `SliverRail` / `SliverToBoxAdapter`.
**Action:** press **COPY REPORT** — it contains the exception, library, context and
stack, and since pass 5 it ends with three diagnostic lines
(`STORAGE: …`, `CACHE: …`, `SETTINGS: …`) wired in through
`SwissErrorCard.reportExtra` — see §8.15 for how to read the `STORAGE` line.
Then reproduce with `flutter run -d <device> --verbose` and read
`adb logcat -s flutter`.

### 8.3 Black / blank screen right after launch on Android
**Cause:** `MainActivity` not extending `AudioServiceActivity` (audio_service binds
the foreground service to the activity).
**Action:** `android/app/src/main/kotlin/com/musify/musify/MainActivity.kt` must stay
`class MainActivity : AudioServiceActivity()`. Already correct — don't "fix" it back
to `FlutterActivity`.

### 8.4 Music doesn't start / nothing plays
Check, in order:
1. **Network** — `curl` a JioSaavn `api.php` call (see §9.2). Empty body = the API
   shape changed, not the app.
2. **Resolution** — the resolver logs each rung it tries (320 → 160 → 96 → direct).
   If all four fail, the song is geo-blocked or the `encrypted_media_url` decryption
   broke; re-run `dart run tool/des_check.dart`.
3. **Engine** — every SoLoud FFI call goes through `_live(handle)`; a dead engine
   goes silent instead of crashing. Look for the engine-init line in the log.
4. **Notification permission** (Android 13+) — playback still works but the media
   notification won't appear without `POST_NOTIFICATIONS`.
5. **It plays, but not immediately** — with **INSTANT PLAY** on (Settings ▸ 04,
   default) the first sample should be audible well under a second: the sample
   table is indexed out of the first 96 KB and the engine is fed AAC frames while
   the rest is still on the wire (§5.7 #32). If a cold track still takes seconds,
   in this order: check the `BUILD:` line in `COPY REPORT` (it must say
   `STREAM-ENGINE` — an older APK has none of this), check the log for a
   `progressive:` line (one per streamed start; if it is missing, the track took
   the download route and the reason is in the line above it), and check
   `STREAM: live=` in the report. A stream that produces no sound within 7 s
   falls back to the download path **by design** and logs `progressive: falling
   back to the download route`. See also §8.16.

### 8.5 The 8D keycap lights up but nothing sounds "8D"
The orbit needs a **stereo** engine (`Channels.stereo`) and headphones to be
audible. Check the calibration sheet: period 5–20 s (default 10), rear low-pass
3200–16000 Hz, reverb wet 0 → 0.24 over 350 ms. If the LED is on but the image
never moves, the 16 ms timer was starved — that shows up in the log.

### 8.6 Home rails are full of skeletons forever
Almost always the catalogue API. Verify with the probe (§9.2). The client sends a
mobile-browser `User-Agent` and forces `ResponseType.plain` + manual `jsonDecode`
on purpose — if someone "simplifies" that to `ResponseType.json`, Dio's transformer
can reject the payload and every rail dies at once.

### 8.7 Analyze reports "named parameter X isn't defined"
You are calling a custom widget with the wrong signature. Use the cheat sheet in §9.1.
The three that have caused this before: `TactileIconKeycap` uses `accent`/`glow`
(**not** `active`/`color` — `active` only sets the border), and `hapticOnPress` now
exists on both keycap types.

### 8.8 `RepeatMode` is ambiguous / has no constant `off`
Flutter's material library exports its own `RepeatMode`. Add
`hide RepeatMode` to the material import in any file that also imports
`services/settings_service.dart`.

### 8.9 Names clash again after a Flutter upgrade
`flutter upgrade` regularly adds exports to `material.dart`. When a name suddenly
becomes "ambiguous" or loses constants, that is why: either `hide` the Flutter name
or rename ours. Currently guarded: `RepeatMode`.

### 8.10 Gradle complains about licences
Licences are already present (`licenses/android-sdk-license`). If a fresh machine
lacks them, install `cmdline-tools` through Android Studio and run
`flutter doctor --android-licenses`.

### 8.11 `flutter test` throws `MissingPluginException`
A test touched a platform channel. Our tests avoid this by disabling `Haptics`, and
by testing pure logic + widgets only. Don't add tests that construct
`PlaybackService` or anything else that talks to a device. `LocalStore` *is* safe
to construct — with no boxes open it runs entirely in memory (§5.6 #31) — and
`test/streaming_test.dart` relies on exactly that.

### 8.12 Downloads stall
`MediaCache` writes to `getApplicationSupportDirectory()`. Check free space, and
remember the cache is an LRU capped at **500 MB** — downloads you requested are
tracked separately from the rolling cache.

### 8.13 A stale queue/position after a crash
State hydration runs before the first paint (Law 8). If it looks wrong, clear app
data once; Hive will be rebuilt from scratch.

### 8.14 A song plays but no mini-player appears at the bottom
The dock is the shell's `bottomNavigationBar`, so it is only visible while the
shell's own route is on top. If a new screen is pushed on the **root** navigator
(`Navigator.of(context)` from outside the chassis, or an explicit
`rootNavigator: true`), it covers the dock and the tab bar. Browse screens must be
pushed on the *nearest* navigator — that is the chassis' nested one
(`§5.6 #29`) — and only the full-screen player uses `rootNavigator: true`. Locked
down by the two tests named "…inside the chassis keeps the dock" and "a root push
is what used to bury the dock".

### 8.15 The heart does nothing / a like is not saved
Check `COPY REPORT` on any fault card: `STORAGE: DEGRADED` plus
`boxes=[…]` says which Hive box failed. With a degraded store every write is
applied in memory only — the UI stays correct for the session and a toast says
`ONLY FOR THIS SESSION // LOCAL STORAGE UNAVAILABLE`. A box that refuses to open
is reset once on the next launch (`deleteBoxFromDisk` + reopen), which clears the
condition. If the toast *does* appear but Liked Songs stays empty, the read path
is the suspect, not the button: `LibraryRepository.isLiked()` caches the id set
and rebuilds it when `LocalStore.revision` changes — a write that forgets
`_bump()` would leave that cache stale.
Since pass 6 the heart reads `LibraryCubit.likedList` directly (§5.7 #33), so a
heart that disagrees with Liked Songs at all means someone reintroduced a second
source of truth — look for `PlayerCubit.isLiked` in the player.

### 8.16 Instant play: diagnosing the stream path
**Ordered check-list.** (1) `BUILD:` in `COPY REPORT` says `STREAM-ENGINE`; if
not, install the newest APK before anything else. (2) Settings ▸ 04 INSTANT PLAY
is on. (3) The log has a `progressive: <id> <rate>Hz <n>s <bytes> from network`
line for the track — `from disk` means it was a cache hit (nothing was fetched,
which is the fastest possible case), and `raw` in place of `<rate>Hz` means the
rendition was not an MP4 (an `_96.mp3` rung, or a file in the vault) and its
bytes were fed to the engine untouched. (4) `STREAM: live=<n>` in the report is 0
when nothing is playing and 1–3 while a track streams or prefetches; an ever
rising number means transfers are not finishing (`MediaCache._unregister`).
**Symptoms → cause:** *no `progressive:` line at all* → the container was
rejected: check the `stream open failed`/`has no usable sample table` lines
right before it, and remember a fragmented MP4 (`moof`) or a non-AAC entry is a
deliberate refusal. *`progressive: falling back to the download route`* → the
engine produced no sound within 7 s (watchdog) or three feeds failed; that track
is blacklisted from streaming for the session, and the user still hears it.
*`STREAM INTERRUPTED` on the player* → a feed failed **after** sound had started;
the engine keeps retrying the same range, and a skip/seek usually recovers it.
*Seeking inside a long track shows a short `BUFFERING`* → the read head jumped
more than 512 KB past the transfer's cursor, so the connection was reopened at
the new offset (a fresh range request, ~0.3 s) and the hole it left is filled in
the background.
**To rule streaming out entirely:** Settings ▸ 04 → INSTANT PLAY off. That path
is the pre-pass-6 code, byte for byte, and is the right thing to compare against
when a song sounds wrong.

### 8.17 A crash report mentions `ByteCoverage`, `Mp4AacIndex` or `StreamSession`
Those three are pure Dart and cannot touch native memory; a stack trace through
them means an *arithmetic* surprise, not an engine fault. The invariants they
maintain, in order: every `stco` offset is absolute (window-base is irrelevant);
`stsz` sizes are consumed in `stsc` runs, several samples per chunk;
`_adtsStarts` has `sampleCount + 1` entries so `totalAdtsBytes` is the stream
length; `ByteCoverage.ranges` is sorted, disjoint and merged (a hole contributes
zero bytes); `assemble` refuses a short window rather than padding it. The tests
in `test/mp4_aac_test.dart` and `test/media_cache_stream_test.dart` pin all of
that against a hand-built MP4 — if they pass, the bug is upstream of the bytes
(network, engine) or in the feed (`PlaybackService._feedFrames`).

---

## 9. Reference

### 9.1 Widget cheat sheet (`core/theme/tactile_decorations.dart`)

```dart
TactileKeycap({required Widget child, VoidCallback? onPressed, EdgeInsetsGeometry padding,
               double? width, double? height, double radius, bool accent, bool glow,
               Color? borderColor, String? tooltip, bool enabled, bool hapticOnPress})

TactileIconKeycap({required IconData icon, VoidCallback? onPressed, double size, double iconSize,
                   bool accent, bool glow, bool active, bool enabled, String? tooltip,
                   bool hapticOnPress})

RecessedWell({required Widget child, EdgeInsetsGeometry? padding, double radius,
              double depth, Color? fill})
SwissPanel({required Widget child, EdgeInsetsGeometry? padding, Color? color,
            Color? borderColor, double radius, bool raised})
SwissPill({required String label, bool selected, VoidCallback? onTap, Widget? leading, bool dense})
TactileSwitch({required bool value, required ValueChanged<bool> onChanged, double width,
               double height, String? semanticLabel})
SwissBackBar({required String title, String? subtitle, VoidCallback? onBack, Widget? trailing})
SectionHeader({required String index, required String title, String? subtitle, Widget? trailing})
SwissBadge({required String text, Color? color, bool filled, IconData? icon})
SwissSkeleton({double? width, double height, double radius})
SwissRule({int divisions, double height})
Hairline({Color? color, double indent, bool vertical})
LedDot({bool active, double size, Color? color})
SwissGrain({required Color color, required double opacity})
TextMarquee({required String text, required TextStyle style, double velocity,
             Duration pauseAfter, double gap})

Haptics: static bool enabled; tap() · press() · commit() · reject()
```

Tokens: `SwissTokens.of(context)`, `SwissTokens.carbon`, `SwissTokens.alabaster`,
`SwissGrid.{u,xs,sm,md,lg,xl,xxl,huge,gutter,miniPlayerHeight,navBarHeight}`,
`SwissType.{label,micro,mono,monoStrong,displayXl,display,displaySm,title,body,bodySm,bodyXs,sansFont,monoFont}`.

> Watch out: `SwissType.mono` is a **TextStyle**; `SwissType.monoFont` is the family
> **name**. Passing the wrong one to `fontFamily:` is error #4 in §5.1.

### 9.2 Catalogue API facts (verified live during development)

```
Base:   https://www.jiosaavn.com/api.php
Common: ?__call=<fn>&_format=json&_marker=0&api_version=4&ctx=web6dot0
Header: a mobile browser User-Agent is required
Note:   force ResponseType.plain and jsonDecode() by hand

content.getAlbumDetails&albumid=<id>        or  webapi.get&token=<permaToken>&type=album
playlist.getDetails&listid=<id>&n=50&p=1
artist.getArtistPageDetails&artistId=<id>&n=20
search.getPlaylistResults / search.getResults            (genre tiles are channels)
Lyrics:  https://lrclib.net/api/*   ·   Artwork fallback: Deezer, then iTunes
Media:   encrypted_media_url, DES-ECB key 38346591 →
         _96.mp4 → replace with _320.mp4 (use _160.mp4 in between)
```

Probe scripts from development still live at
`%TEMP%\opencode\saavn_probe*.js` and can re-verify every endpoint above.

### 9.3 The eight defensive laws (PRD §5) and where they live

1. Non-blocking, time-boxed startup → `main.dart` (`_guarded`, 4 s)
2. `AudioServiceActivity` + foreground media service → `MainActivity.kt`, manifest, `audio_handler.dart`
3. `IndexedStack` tabs → `shell/main_shell_screen.dart` — the four screens are an
   `IndexedStack` inside a *nested* chassis navigator, which is what keeps the
   mini-player and tab bar visible over every pushed detail screen (§5.6 #29)
4. Custom `ErrorWidget.builder` → `core/theme/swiss_error_card.dart` (`reportExtra`
   appends the storage/cache/settings diagnostics to `COPY REPORT`)
5. Strict viewport constraints → every screen (max widths, short-viewport
   guards); slivers vs boxes is enforced by `SliverRail` (§5.4 #24)
6. FFI handle validation → `_live(handle)` in `playback_service.dart`
7. Null-safe JSON parsing → `jiosaavn_client.dart`, pinned by
   `test/jiosaavn_parsing_test.dart` through the `@visibleForTesting` seams
   (`parseSong`, `parseRailItem`, `parseCollection`, `rememberedEncrypted`,
   `decryptMediaUrl`, `rewriteBitrate`) — see §5.4/§7
8. State hydration on launch → `local_store.dart` + `bootstrapServices()`, with
   `Track.fromMap`/`listFrom` hostile-map tests in
   `test/jiosaavn_parsing_test.dart`. A box that will not open degrades to an
   in-memory store rather than silent no-ops (§5.6 #31)

**The ninth law, learned in pass 6:** *the fast path must never be the only path.*
Every attempt to make playback faster since pass 5 has been built as an
**optimization with a fallback**, never as a rewrite of the working code:

* progressive streaming refuses anything it cannot prove — a fragmented MP4, a
  non-AAC sample entry, a missing `Content-Length`, an inconsistent sample table —
  and returns `false`, whereupon the pre-pass-6 download-then-load route runs
  unchanged (`PlaybackService._startProgressive` → `_resolveFor`);
* if the stream produces no sound within 7 s, the watchdog falls back *and
  blacklists that track for the session*, so a bad file cannot loop;
* the setting that turns it on (`instantStart`) is the comparison baseline: off
  means byte-for-byte the old behaviour;
* the finished stream is renamed into the cache as if `ensure()` had downloaded
  it, so a stream and a download can never disagree about what is on disk.

---

## 10. Open items / next milestones

1. **Install the pass-6 APK and confirm the five reports on the phone** — the
   artifact is rebuilt and *fresh* (newer than every `lib/` file; see §7.1):
   copy `build\app\outputs\flutter-apk\app-release.apk` to the device or
   `flutter install -d <device-id>`. **First, check the build marker**: Settings ▸
   ABOUT (or the first line of any `COPY REPORT`) must read
   `1.0.2+3 · STREAM-ENGINE · 2026-10-17`. If it does not, the installed APK is an
   older build and none of this pass is on the device. Then, in this order:
   * **instant play** — tap a cold song: sound should start in well under a second
     (log line `progressive: <id> …`). A song that was played once already has no
     excuse at all: it is on disk (`from disk`). If a track still takes seconds,
     note whether the log shows `falling back to the download route` — that is
     the safety net, not a failure, and §8.16 lists the next checks. Toggle
     Settings ▸ 04 **INSTANT PLAY** off to compare with the old path.
   * **the heart in the player** — tap it in the full-screen player: it must fill,
     toast `ADDED TO LIKED SONGS`, and appear under Library → Liked Songs, and the
     mini-player heart must agree with it. It reads the same list as the Liked
     Songs screen by construction (§5.7 #33), so any disagreement is a bug worth
     reporting with `COPY REPORT`.
   * **playlist import** — import a `.m3u`/`.json`/`.txt`: after the scan the sheet
     must ask **CREATE PLAYLIST** or **ADD TO EXISTING**, and the playlist must
     exist with the matched songs in it (§5.7 #34).
   * **bottom nav** — no ordinals, just icon + label (§5.7 #35).
   * **Home pills** — ALL MUSIC / 8D SPATIAL / OFFLINE READY must each land on
     their own rail or section (§5.7 #36).
   Then the rest of the end-to-end list: lock-screen controls, notification
   surviving backgrounding, playback continuing while paused-and-resumed, and the
   8D orbit audible on headphones. Expect future device-only errors to arrive one
   at a time — that is normal for the first runs of a codebase this young; each one
   gets a row in §5.7 and an entry in §8.
2. **Could not be verified without a device** (be honest about these): that the
   SoLoud native libraries load on ARM (they are packaged and correctly named, but
   nothing has called them on Android yet), `AudioServiceActivity` ↔ foreground
   service binding, `POST_NOTIFICATIONS` prompt on Android 13+, and the 16 ms 8D
   orbit timer surviving backgrounding. Since pass 6, add to that list: the
   pull-buffer stream itself (`setPullBufferStream` + `addPullBufferDataStream`
   are exercised only through the FFI on a real engine), and Android's behaviour
   when a transfer is still writing while the app is backgrounded.
3. ~~**Nice to have:** a `flutter test` case for `Track.fromJson` with hostile
   payloads~~ — **done** in pass 4: `test/jiosaavn_parsing_test.dart` (28 cases)
   covers hostile JioSaavn payloads, the DES fixture, the `_96 → _320` rewrite and
   rotten `Hive` maps. See §5.4 and §7. Pass 6 added
   `test/mp4_aac_test.dart` (the demuxer, byte-exact, against a hand-built MP4)
   and `test/media_cache_stream_test.dart` (staged sessions, `ByteCoverage`) — the
   range-merge bug they caught on their first run is exactly why they exist.
4. **Cosmetic:** the `windows/` directory is unused and can be deleted; nothing in
   the Android build references it.
5. **If start time is still the complaint, these are the next levers** (deliberately
   *not* guessed at in pass 5, because each trades quality or complexity for
   latency):
   * start the first play of a track at 160 kbps and warm the 320 in the
     background, switching on the next play — the ladder already exists, so this
     is a policy change in `MusicRepository.resolvePlayable`;
   * feed `flutter_soloud`'s `setPullBufferStream` with ADTS AAC read over HTTP
     ranges: real progressive playback, at the cost of writing a parser and a
     buffer-feeding source — the only route to true streaming inside this engine;
   * raise `MediaCache.laneCount` (4 today) if the CDN turns out to allow more
     connections without penalising the extra sockets.

---

## 11. Pass 7 - Architectural restyle (1.0.3+4 // ARCHITECTURAL)

**Scope.** The entire UI was re-skinned to the Stitch "Architectural" reference
designs (`docs/design/stitch/`, 9 screens) in *both* modes: paper-light
*Alabaster* and obsidian *Carbon*. This pass changed paint, geometry and type
only - every cubit, service, route and screen contract is untouched.

**What changed.**

* `core/theme/swiss_tokens.dart` - new palettes for both themes: light paper
  `#F9F9F9` with ink `#1A1C1C` as the signal colour; dark obsidian `#0D0E11`
  with champagne `#E2B170`. Radii 16/28/pill, a retuned type ramp, soft ambient
  shadows, reduced grain.
* `core/theme/tactile_decorations.dart` - the component kit was flattened:
  paper `SwissPanel`, soft `RecessedWell`, stadium `TactileKeycap` (plus
  `ghost` and `foregroundColor` for accent ghost buttons), compact caps
  `SectionHeader`, pill `SwissBadge`/`SwissPill`, dot-accent `SwissBackBar`.
* **Shell** - one docked plane: the floating mini-player card (accent mono
  title, bitrate badge, 8D chip, accent play, progress hairline inside the
  card) over the icon + caps nav bar (grid_view / search / folder_open /
  settings), the live tab in the signal colour, soft upward shadow instead of a
  hard edge.
* **Headers** - every tab opens with the MUSIFY wordmark row, a `// TAB`
  eyebrow with the signal dot and right-aligned telemetry; `ScreenHeader` grew
  an optional display title for Settings.
* **Cards and rows** - paper cards (hairline border, soft shadow), bead
  scrubbers (ink shell, canvas pip), accent index numerals, OFFLINE/320 KBPS
  badges on every track row, 28 dp play beads on rail cards, `TrackCard`
  rebuilt as a floating card.
* **Now Playing** - big artwork with a SPATIAL 8D badge, a playing/paused
  status pill, the 64 dp accent play button on expanded transport, and a
  four-segment action strip (LYRICS / SPATIAL 8D / QUEUE / SLEEP) replacing the
  8D module block; the orbit telemetry line with a CALIBRATE link sits under
  it, the volume control is a stadium pill. The 8D module itself is unchanged
  in Settings 02, and long-press on the strip segment opens calibration.
* **Sheets** - raised paper slab, 32 dp top radius, dot + caps headers; the
  rename / import / new-playlist fields are stadium pills like the search
  fields.
* **Fonts** - Plus Jakarta Sans (OFL) is bundled as the voice; JetBrains Mono
  keeps the technical register.

**Gates.** `flutter analyze` clean. `flutter test` 69/69 green with no test
edits (the token and component APIs kept their shapes). Release APK rebuilt on
this stamp - ARM64 + ARMv7 only, Impeller. The artifact was verified from the
APK itself with `aapt2 dump badging`: `com.musify.musify` 1.0.3 (build 4),
minSdk 26 -> targetSdk 36, `native-code: 'arm64-v8a' 'armeabi-v7a'` only,
43.6 MB.

**Device checklist (open).** The five pass-6 device checks in section 10 item 1
still stand; the marker to verify on the phone is now
`1.0.3+4 // ARCHITECTURAL`. What is new to look at on hardware, beyond those:
the light/dark switch (Settings 05) repainting every token, the dock shadow on
OLED, the mini-player progress line ticking under the card, and the Now Playing
action strip toggling 8D with long-press opening the calibration sheet.

---

## 12. Pass 8 - Minimal Premium De-Clutter Redesign (Stitch Project 5632894428465236805)

**Scope.** Addressed the UI feeling "a bit clustered" by transforming the visual hierarchy into a minimal, clean, and unclustered layout inspired by Stitch project `5632894428465236805` ("Minimal Premium Music UI"). All existing functionality (streaming engine, 8D audio calibration, offline vault, downloading, playlist imports, lyrics, equalizer) was strictly preserved.

**Screens & Design System Updates:**
1. **Design Tokens & Geometry (`swiss_tokens.dart`, `tactile_decorations.dart`):**
   - Palette refined to deep Obsidian (`#0A0B0E`), soft elevated surfaces (`#12141A`, `#181B22`), champagne filament gold (`#E2B170`), and luminous hairlines (`0x14FFFFFF`).
   - Clean radii: `radiusSm: 8.0`, `radius: 16.0`, `radiusLg: 24.0`, `radiusFull: 999.0` (stadium pills).
   - Removed harsh brutalist borders, excessive `//` headers, and jagged double-borders.
   - Refined `SwissPill` with smooth stadium shape, subtle background when unselected, and warm amber glow when active.
2. **Home Screen (`home_screen.dart`, Stitch Screen 1):**
   - Header with clean typography, settings/equalizer quick action (`Icons.tune`), and refresh/sync indicator.
   - `_QuickGrid` with soft card surfaces, 14px radius, heart overlay for Liked Songs, and offline vault download badge.
   - Added `_AudioOutputStrip` (`Direct Audio Stream` / `Lossless 32-bit / 384kHz · Studio Master` status pill card).
   - Ensured all rail and list items maintain breathing room without clutter.
3. **Search Screen (`search_screen.dart`, Stitch Screen 2):**
   - Clean 44px stadium search pill with search icon prefix, `Search tracks, artists, acoustics...` placeholder, and subtle circular clear button.
   - Replaced vertical recent searches stack with horizontal scrolling `_RecentChip` pills featuring `history` icon, query, and tap/remove actions.
   - Featured `_TopResult` card with 72x72 rounded artwork, `8D SPATIAL` and bitrate format chips, "Play Now" primary action button, `playlist_add` button, and `FLAC · 24-BIT` audio specs tag.
   - `TrackListTile` in search results updated with `showArtwork: true` (40x40 rounded cover art) for visual matched tracks.
4. **Library Screen (`library_screen.dart`, Stitch Screen 3):**
   - Clean subtitle: `${state.entries.length} items • ${state.liked.length} liked • ${state.downloads.length} offline`.
   - Stadium search filter with search icon and sort dropdown.
   - Pinned `Liked Songs` and `Offline Vault` rows with push-pin icon badge, heart/download cover overlays, and `FLAC`/`OFFLINE` format pills.
   - Active `_DownloadStrip` modernized to a sleek card with precision hairline gauge progress bar.
5. **Shell & Mini-Player (`main_shell_screen.dart`, `mini_player_bar.dart`):**
   - Bottom navigation bar with soft upward shadow and subtle border.
   - Floating mini-player island dock with 16px radius, hairline border, and gentle drop shadow.

**Quality Gates:**
- `flutter analyze`: **0 issues found!**
- `flutter test`: **69/69 passed** (100% green).

