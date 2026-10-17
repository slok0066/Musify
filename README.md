# Musify

A Spotify-class Android music app with an **architectural-minimalist** interface
(paper-light *Alabaster* and obsidian *Carbon*, both first-class) and a
**1-tap real-time 8D spatial audio** engine.

Musify streams the full JioSaavn catalogue at **320 kbps**, keeps a rolling
500 MB on-disk cache, works fully offline for anything you download, and renders
the whole product as a quiet instrument panel: soft paper cards, stadium pills,
a bead scrubber, monospace telemetry and a single signal colour - ink in light,
champagne in dark.

> Built from the PRD in `prd/`. Where the shipped code deviates from that
> document, the deviation is listed under [Honest deviations](#honest-deviations)
> — there is exactly one, and it is deliberate.
>
> **Working on the code?** `docs/IMPLEMENTATION_LOG.md` is the detailed build
> journal: every compiler error this project has produced, its root cause, the
> exact fix, plus a symptom → cause → action troubleshooting index and a widget
> API cheat sheet.

---

## Quick start

```bash
flutter pub get

# Android device / emulator (ARM64 or ARMv7) — the only shipping target
flutter run -d <android-device-id>

# Release APK — ARM-only (arm64-v8a + armeabi-v7a), single artifact.
# Do NOT add --split-per-abi: see docs/IMPLEMENTATION_LOG.md §8.0b.
flutter build apk --release --target-platform android-arm --target-platform android-arm64

flutter analyze
flutter test      # 69 tests, no device/network/audio engine needed
```

Requires Flutter **3.47.x / Dart 3.13.x** or newer. Android `minSdk 26`
(Android 8.0), `targetSdk 36`.

---

## What it does

| Surface | Behaviour |
| --- | --- |
| **Home** | Live rails (trending, new releases, charts, daily mixes, genre tiles), a **8D SPATIAL PICKS** rail, skeleton loading, pull-to-refresh, offline banner |
| **Search** | 350 ms debounced multi-search (songs, albums, artists, playlists) with filter pills and recent-search persistence |
| **Library** | Liked / Playlists / Downloads / Import in one screen, list ⇄ grid layouts, rename + delete, live download progress, YouTube & Spotify playlist import |
| **Now Playing** | Artwork, the 8D keycap + calibration sheet, seekbar with buffering readout, transport, queue counter, volume, FFT/waveform analyser, synced lyrics, queue editor, sleep timer |
| **Settings** | Streaming quality ladder, **instant play**, 8D calibration, 10-band EQ + bass boost, crossfade, storage manager, backup export/import, theme, haptics, about |

**Playback** is `flutter_soloud` (C++ SoLoud, Impeller-friendly, no `media_kit`).
Android lock-screen/notification/media-button integration is `audio_service` +
`audio_session`, running as `AudioServiceActivity` so the engine keeps its
audio focus and its 16 ms 8D orbit timer while backgrounded.

**Streaming waterfall** — tried in order, first hit wins:

1. JioSaavn `_320.mp4` (AAC, decrypted from `encrypted_media_url`)
2. JioSaavn `_160.mp4`
3. JioSaavn `_96.mp4`
4. The direct URL as-is
5. A verbatim on-disk copy from the cache / Offline Vault

Each rung is *probed* before it is downloaded: a one-byte `Range` request buys the
file's real length (so the transfer can be split over four connections) and rejects
the error pages the CDN serves for delisted renditions — by content type **and** by
the container's magic bytes, so a stored file is always audio.

**Instant play.** `flutter_soloud` decodes a whole MP4/M4A to PCM on load, so a
cold track used to cost *whole download + decode*. Musify now demuxes the
container itself: `services/mp4_aac.dart` reads the sample table out of the first
96 KB, `MediaCache.openStream()` serves the bytes *while* one re-positionable
transfer is still writing them, and `PlaybackService` feeds the engine
(`setPullBufferStream`) ADTS-wrapped AAC frames as it asks for them — first sample
in a few hundred milliseconds instead of after ten megabytes. A rendition that is
not an MP4 (the older `_96.mp3` rungs, or a file already in the vault that the
engine decodes natively) skips the repacking entirely and streams raw, so the fast
path does not depend on the container. The finished file is
renamed into the cache exactly as a download would have been, so the next play is a
plain disk read and the Offline Vault sees one file, not two. Nothing above is on
the critical path if it fails: every refusal (no `Content-Length`, a fragmented
MP4, a non-AAC sample entry, an inconsistent table) and a 7 s silence watchdog fall
back to the download-then-load route. `TrackPrefetch` still warms the head of a list
when it opens, and the player still prefetches the next queue entry. Toggle it in
Settings ▸ 04 → **INSTANT PLAY** (default on; off is byte-for-byte the old path).

Lyrics come from **LRCLIB** (synced where available), artwork from the
JioSaavn payload with **Deezer → iTunes** as a fallback. Every source is free —
no paid API keys anywhere in the project.

### Real-time 8D

The orbit is computed in Dart and pushed into SoLoud's 3D mixer every 16 ms:

```
x = 2·sin(θ)            z = 2·cos(θ)
pan   = 0.85·sin(θ)     rear low-pass = 3200 … 16000 Hz · (cos θ + 1)/2
freeverb: roomSize 0.72, damp 0.50, wet 0 → 0.24 over 350 ms
period: 5–20 s (default 10 s)
```

The engine is initialised `Channels.stereo`; every FFI call is wrapped in a
`_live(handle)` guard, so a dead engine degrades to silence instead of a crash.
Headphone connect/disconnect is picked up through `audio_session` and can arm 8D
automatically.

---

## Architecture

```
lib/
  main.dart                     non-blocking, time-boxed startup (4 s per step)
  app.dart                      MaterialApp, themes, app-wide providers
  core/theme/                   SwissTokens, theme, keycaps/wells, fault card
  core/utils/                   debouncer, formatters
  data/models/                  Track, Collection, Lyrics, UserPlaylist
  data/datasources/             jiosaavn, lyrics, artwork, playlist importer
  data/sources/local_store.dart Hive/SharedPreferences persistence
  data/repositories/            MusicRepository, LibraryRepository
  services/                     settings, media cache, backup, connectivity
  services/player/              PlaybackService (engine), audio_handler (OS bridge)
  services/service_locator.dart get_it wiring, bootstrapServices, warmUpAudio
  presentation/cubits/          Home, Search, Collection, Library, Player,
                                Settings, Navigation
  presentation/shell/           IndexedStack + nav bar + mini player
  presentation/screens/         home, search, collection, library, now_playing,
                                settings
  presentation/widgets/         the reusable Swiss control kit
```

Layering is strict: **screens never touch a datasource**. A Cubit talks to a
repository, a repository talks to datasources, and the player is driven only
through `PlayerCubit` → `PlaybackService`.

### The eight defensive laws

1. **Non-blocking startup** — every boot step is wrapped in a 4 s timeout; a
   dead network, disk or audio device degrades one subsystem, not the app.
2. **`AudioServiceActivity`** — background playback survives the UI being
   reclaimed; the notification is a real `MediaSession`.
3. **`IndexedStack` tabs** — tab state (scroll position, search query, queue
   view) survives switching, and no tab rebuilds on navigation.
4. **Custom `ErrorWidget.builder`** — a failed widget paints a Swiss fault card
   with copy-report/dismiss instead of the red screen of death.
5. **Strict viewport constraints** — every screen is constrained for wide
   (tablet/desktop) and short viewports; nothing relies on a phone aspect ratio.
6. **FFI handle validation** — `_live(handle)` guards every SoLoud call.
7. **Null-safe JSON parsing** — every field from JioSaavn is read defensively;
   one malformed track cannot poison a rail.
8. **State hydration on launch** — queue, position, likes, downloads and
   settings are restored before the first paint, so the app never opens empty.

### Layout rules the analyzer cannot enforce

Three Flutter mistakes type-check perfectly and only explode at first paint (or,
for the last one, into a missing widget), so they are encoded as widgets/rules
instead of comments:

* **Slivers vs boxes.** `CustomScrollView.slivers` is typed `List<Widget>`, so a
  box widget type-checks and then throws
  `type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of 'child'`
  when the viewport inserts it. The rule: **in a slivers list use `SliverRail`
  (or `SliverToBoxAdapter`); in a box list use `SwissRail`.** The empty branch of
  a rail must still return a *sliver* — `SliverRail` does. Regression test:
  "SliverRail is a real sliver — empty and populated".
* **Bounded heights for horizontal lists.** A horizontal `ListView` inside a
  vertical scroll view needs an explicit height (`SwissRail` defaults to 214) or
  it fails with unbounded constraints.
* **Route level = chrome level.** The mini-player and the tab bar are the shell
  `Scaffold`'s `bottomNavigationBar`, so they exist only while the shell's own
  route is on top. The rule: **browse screens push on the nearest (chassis)
  navigator; only the full-screen Now Playing route uses
  `rootNavigator: true`.** Locked down by the twin tests "a detail screen pushed
  inside the chassis keeps the dock" and "a root push is what used to bury the
  dock".

Full symptom → cause → action table: `docs/IMPLEMENTATION_LOG.md` §8, plus
**§8.0d — "Runtime-only faults: the audit checklist"**: the six
`flutter analyze` blind spots (box-in-slivers, unbounded horizontal lists,
`firstWhere` without `orElse`, `.first`/`[0]` on empty collections, null
assertions, shared `ScrollController`s) together with the `grep` for each.

---

## Honest deviations

**1. The YouTube fallback was removed (the one deliberate deviation).**

The PRD's resolver waterfall was `JioSaavn → YouTube → Piped`. In practice:

* `saavn.dev` (the PRD's suggested proxy) is dead.
* Public Piped instances answered **525 / 502** throughout development.
* `youtube_explode_dart` *search* worked, but every stream-extraction request
  returned `VideoUnplayableException` — YouTube now requires a PO-token /
  attestation flow that cannot be satisfied from a plain Dart client without a
  botguard implementation or a paid key, both of which the PRD forbids.

Rather than ship a fallback that silently fails, the ladder was replaced with
what actually resolves: **the official JioSaavn internal API**
(`www.jiosaavn.com/api.php`, the same endpoint the web player uses) at
320 → 160 → 96 kbps, plus the direct URL and the on-disk copy as final rungs.
The Settings ▸ About panel and this section both say so in-product.

The PRD's "zero paid API keys" requirement is fully satisfied: JioSaavn,
LRCLIB, Deezer and iTunes need no key at all.

**2. Minor, non-behavioural notes.**

* Fonts (Plus Jakarta Sans, JetBrains Mono) are **bundled as assets** rather than fetched at
  runtime via `google_fonts`, so the typographic system renders identically with
  no network — a hardening of the PRD's intent, not a change in design.
* Cache/download directories live under `getApplicationSupportDirectory()`.
* Package pins were refreshed to current releases (`flutter_soloud 5.2.1`,
  `audio_service 0.18.19`, `audio_session 0.2.4`, `flutter_bloc 9.1.1`,
  `cached_network_image 4.0.4`, `share_plus 13.3.1`, `pointycastle 4.0.0`).
  `pointycastle 4.x` ships no single-DES engine, so the media-URL decryption uses
  the proven `DESedeEngine` with the 8-byte key repeated three times — byte-for-byte
  identical output to `DES-ECB`.

---

## Verification notes

* `tool/des_check.dart` — decryption proof for `encrypted_media_url`
  (key `38346591`), including the `_96 → _320` upgrade.
* `tool/adts_check.dart` — frame-exact proof of the MP4 → ADTS demuxer against a
  live 320 kbps file (sample count, per-frame ADTS lengths, absolute file offsets,
  tail windows) without a device.
* Probe scripts for the catalogue API live outside the repo
  (`%TEMP%\opencode\saavn_probe*.js`) and can re-verify every endpoint fact.
* `flutter test` — **69 tests, all green with no device, network or audio engine**:
  `test/widget_test.dart` (formatting contract, theme tokens, keycap behaviour,
  dock survives a pushed detail screen), `test/jiosaavn_parsing_test.dart` (hostile
  catalogue payloads, the DES fixture, rotten Hive maps),
  `test/streaming_test.dart` (range splitting, container sniffing, error-page
  rejection, the rendition ladder, a store that runs without Hive boxes),
  `test/mp4_aac_test.dart` (the demuxer against a hand-built MP4, byte-exact ADTS
  assembly, coverage arithmetic) and `test/media_cache_stream_test.dart` (staged
  sessions, cache-hit short-circuits, the unreachable-URL fallback).
* Release build verified from the artifact itself: `app-release.apk`
  (43.6 MB, `com.musify.musify` 1.0.3 (build 4), minSdk 26 → targetSdk 36) contains
  `arm64-v8a` + `armeabi-v7a` native libraries only, including the SoLoud engine
  and its codecs — checked with `aapt2 dump badging` and a zip listing, not
  assumed from config. The build stamp (`1.0.3+4 // ARCHITECTURAL · 2026-10-17`)
  is printed in Settings ▸ ABOUT and at the top of `COPY REPORT`.
* Musify is **Android-only**: `flutter analyze` and `flutter test` run on the
  development machine, but there is no desktop target to run the app on. The
  full error/fix history is in `docs/IMPLEMENTATION_LOG.md`.

## Legal

Musify is a personal-use research/learning project. It streams from JioSaavn's
public endpoints and does not host, redistribute or monetise any catalogue
content. Use it on your own machine, with your own account-free session, at your
own risk.
