<div align="center">

<img src="assets/icon/app_icon.png" alt="Musify app icon" width="112" />

<h1>Musify</h1>

<p><strong>A complete, ad-free Android music player.</strong><br />
320 kbps streaming · offline vault · one-tap real-time 8D · a monochrome instrument-panel interface.</p>

<p>
  <a href="https://github.com/slok0066/Musify/releases/latest"><img src="https://img.shields.io/github/v/release/slok0066/Musify?style=flat-square&amp;label=release&amp;color=0A0B0E" alt="Latest release" /></a>
  <a href="#install"><img src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?style=flat-square&amp;logo=android&amp;logoColor=white" alt="Android 8.0+" /></a>
  <a href="#build-from-source"><img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Flutter 3.47" /></a>
  <a href="#verification"><img src="https://img.shields.io/badge/tests-84%20passing-2EA043?style=flat-square" alt="84 tests passing" /></a>
  <a href="#data-sources"><img src="https://img.shields.io/badge/paid%20API%20keys-0-0A0B0E?style=flat-square" alt="Zero paid API keys" /></a>
</p>

<p>
  <a href="https://github.com/slok0066/Musify/releases/latest"><strong>Download APK</strong></a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="docs/IMPLEMENTATION_LOG.md">Engineering log</a>
</p>

</div>

---

Musify is a personal, Spotify-class Android music app: the full JioSaavn catalogue at up to **320 kbps**, a rolling on-device cache, permanent offline downloads, synced lyrics, playlist import, a 10-band equalizer, and a **real-time 8D spatial engine** you can toggle in one tap.

No accounts. No ads. No subscriptions. No paid API keys.

It is built with `flutter_soloud` for playback, `audio_service` + `audio_session` for the lock screen and audio focus, `flutter_bloc` + `get_it` for the app, and `hive_flutter` + `shared_preferences` for state.

---

## Install

**Requirements:** Android 8.0 (API 26) or newer, on an ARM64 or ARMv7 device.

1. Open the [latest release](https://github.com/slok0066/Musify/releases/latest).
2. Download the APK for your phone:
   - **`app-arm64-v8a-release.apk`** — almost every Android phone from roughly 2017 onward.
   - **`app-armeabi-v7a-release.apk`** — older 32-bit ARM devices.
3. Open the file and allow installation from this source when Android asks.
4. Launch Musify. The one-time credits screen appears only on a fresh install.

The app also checks GitHub for updates on launch and from **Settings ▸ CHECK FOR UPDATES**. It downloads the ARM64 build and hands it to Android's package installer; 32-bit devices should update from the release page.

To confirm exactly which build is installed, open **Settings** and read the build stamp at the bottom. It follows the form:

```text
MUSIFY 1.0.15+16 // HOLD · 2026-10-18
```

---

## Latest release — v1.0.15 "HOLD"

- **Seeks hold their ground.** Dropping the scrubber on a part that is not loaded stops there and continues from that spot as soon as its bytes arrive — no drift back to the old position, no restart from the top.
- **Faster loading.** The first feed of every new window is half the normal size, so the first sound arrives roughly twice as quickly. Far seeks on a song already on disk are served straight from the file instead of decoding the whole track first.
- **Continuous scrubbing is safe.** Rapid drags coalesce into one final seek, a failed seek lands on the drop position instead of zero, and the seek watchdog no longer gives up while the engine is merely starvation-paused.
- **Audio focus.** Musify asks Android for focus when it plays, so a call or another app such as YouTube pauses it. A call ending resumes playback; a permanent focus loss does not. Unplugging headphones pauses too.

[Full release notes](https://github.com/slok0066/Musify/releases/tag/v1.0.15) · [All versions](https://github.com/slok0066/Musify/releases)

---

## What's inside

| Surface | Highlights |
| --- | --- |
| **Home** | Jump Back In, Continue Listening, Made For You daily mixes, Trending Now, Top Charts, New Releases, Mood Playlists, Recently Cached, genre tiles, and a dedicated 8D picks rail. Pull-to-refresh, skeleton loading, and an offline banner. |
| **Search** | 350 ms debounced multi-search across songs, artists, albums, and playlists, with facet pills, recent queries, and load-more paging. |
| **Library** | Liked Songs, playlists, downloads, albums, and artists in one place. List/grid layouts, sort, search, create/rename/delete, live download progress, and public YouTube/Spotify playlist import. |
| **Now Playing** | Full-size artwork, a responsive seekbar with buffer readout, transport controls, queue editor, synced lyrics, 8D calibration, sleep timer, volume, and like/download actions. |
| **Settings** | Quality ladder for Wi-Fi, mobile data, and downloads; 8D parameters; 10-band parametric EQ + bass boost; crossfade, gapless preload, prefetch, and **Instant Play**; Carbon/Alabaster themes; haptics; storage tools; JSON backup/restore; update check. |
| **Shell** | Persistent `IndexedStack` tabs, a docked mini-player, and a full-screen player route that opens above the shell. |

---

## How it works

### Playback engine

Playback runs on **`flutter_soloud`** — C++ SoLoud over Dart FFI, with no `media_kit`. A foreground `audio_service` instance owns the MediaSession, lock-screen controls, notification, and hardware media buttons; `audio_session` handles focus and headphone events. The engine is warmed up after the first frame, so launch never waits on an audio device.

### Instant Play: sound before the download finishes

`flutter_soloud` normally decodes a whole MP4/M4A before it can play a sample. Musify avoids that wait for streams:

1. A one-byte `Range` request probes the chosen rendition: real file length, content type, and the container's magic bytes. Dead or error-page renditions are rejected before a download starts.
2. `services/mp4_aac.dart` reads the sample table from the beginning of the file.
3. `MediaCache.openStream()` starts **one sequential transfer** and serves bytes while that transfer is still writing them.
4. `PlaybackService` feeds ADTS-wrapped AAC frames into the engine through `setPullBufferStream`. The first feed is 96 KB rather than the normal 192 KB window, so the first sound lands sooner.
5. When the transfer completes, the file is finalized into the cache exactly as a download would be. The next play is a plain disk read.

Non-MP4 renditions stream raw, so the fast path does not depend on the container. Every refusal — no `Content-Length`, a fragmented MP4, a non-AAC sample entry, an inconsistent table — falls back to the classic download-then-load route. A silence watchdog hands over if the progressive route stalls.

### Seeking that holds its ground

Seeking is a three-path system. The fast path is never the only path.

| Situation | What happens |
| --- | --- |
| Target inside the engine's decoded window | Native in-buffer seek on the existing voice. Instant; no source rebuild, no restart. |
| Target outside the window, remote stream | The old voice is stopped, a fresh pull stream is rebuilt sequentially at the target, and buffering is shown. Playback continues from the drop as soon as its bytes arrive. |
| Target outside the window, cached/downloaded track | The same rebuild, served from disk. No whole-file M4A decode. |
| Finger still on the scrubber | `hintSeek` moves the single transfer towards the target in throttled steps, so the release lands on warm bytes. |
| Rapid consecutive releases | The newest intent wins; a pending seek is consumed before the in-flight operation returns. |
| The stream route fails | A download-route handoff lands at the drop position, never at zero, and preserves the paused state. |

The chain is **in-buffer seek → rebuild at target → download handoff**. Each branch ends with sound, and the fallback position is always the position the user chose.

### Cache, downloads, and the Offline Vault

Every completed stream becomes a cache file, so replaying a track is a local read. The cache is a bounded LRU; **CLEAR STREAM CACHE** never touches offline downloads. Downloads are written to a permanent folder and exposed as the **Offline Vault**, with the same transfer machinery driving progress and consistency.

Backups are portable JSON: liked songs, playlists, history, and preferences, exportable and restorable from Settings.

### Real-time 8D

The orbit is computed in Dart and pushed into SoLoud's 3D mixer every 16 ms:

```text
x = 2·sin(θ)              z = 2·cos(θ)
pan   = 0.85·sin(θ)       rear low-pass = 16 kHz → 3.2 kHz as the voice moves behind
freeverb: roomSize 0.72, damping 0.50, wet 0 → 0.24 over 350 ms
period: 5–20 s (default 10 s)
```

The engine runs stereo. Every FFI call is guarded by a `_live(handle)` check, so a dead engine degrades to silence rather than crashing the widget tree. 8D can arm automatically when headphones connect.

### Audio focus, calls, and interruptions

Musify requests audio focus when playback starts. That is what makes Android deliver interruption events at all:

- A **transient** interruption (a call, an assistant prompt) pauses playback and resumes it when the interruption ends — but only if Musify paused it.
- A **permanent** focus loss (another media app such as YouTube) pauses playback and does not auto-resume.
- Unplugging headphones pauses playback.
- Transient duck requests lower the volume instead of stopping.

### Data sources

| Need | Source | Key required? |
| --- | --- | --- |
| Catalogue, search, stream URLs | JioSaavn web-player API (`www.jiosaavn.com/api.php`) | No |
| Synced and plain lyrics | [LRCLIB](https://lrclib.net) | No |
| Artwork fallback | Deezer → iTunes | No |
| Playlist import | Public YouTube and Spotify playlist pages | No |

The streaming ladder is the requested JioSaavn tier (320 → 160 → 96 kbps), then the direct URL, then a cached/offline copy. Each rung is probed before it is used. Artwork comes from the JioSaavn payload first, with Deezer and iTunes as fallbacks. Playlist import re-finds each song on JioSaavn; it does not extract audio from YouTube or Spotify.

---

## Interface

Two first-class themes, switched manually or with the system:

- **Carbon** — near-black chassis, white ink, white accent, restrained grain.
- **Alabaster** — paper-white chassis, black ink, black accent, no grain.

The system is deliberately monochrome. Colour is reserved for state: positive, warning, danger. Typography is **Inter**, **JetBrains Mono**, and **Plus Jakarta Sans**, bundled as assets so the interface renders identically with no network. Controls are tactile keycaps, stadium pills, hairline borders, soft ambient shadows, and monospace telemetry. The scrubber is a bead on a rail, not a generic Material slider.

All three fonts ship in `assets/fonts/`; there is no `google_fonts` runtime fetch. Interface studies and screen references live in [`docs/design/stitch/`](docs/design/stitch/).

---

## Architecture

```text
lib/
├── main.dart                     time-boxed bootstrap; audio service + warm-up
├── app.dart                      MaterialApp, themes, app-wide providers
├── core/
│   ├── build_info.dart           version, build number, release tag, date
│   ├── theme/                    SwissTokens, theme, keycaps, fault card
│   └── utils/                    debouncer, formatters
├── data/
│   ├── models/                   Track, Collection, Lyrics, UserPlaylist
│   ├── datasources/              JioSaavn, LRCLIB, artwork, playlist import
│   ├── sources/local_store.dart  Hive/SharedPreferences persistence
│   └── repositories/             MusicRepository, LibraryRepository
├── services/
│   ├── player/
│   │   ├── playback_service.dart engine, queue, seek state machine, 8D, EQ
│   │   └── audio_handler.dart    audio_service bridge, focus, interruptions
│   ├── media_cache.dart          cache, downloads, progressive sessions
│   ├── mp4_aac.dart              MP4 sample table → ADTS frames
│   ├── update_service.dart       GitHub manifest + in-app APK download
│   ├── backup_service.dart       JSON export/import
│   ├── network_monitor.dart
│   ├── settings_service.dart
│   └── service_locator.dart      get_it wiring; bootstrap and warm-up
└── presentation/
    ├── cubits/                   Home, Search, Collection, Library, Player,
    │                             Settings, Navigation
    ├── shell/                    IndexedStack, nav bar, mini-player
    ├── screens/                  home, search, collection, library,
    │                             now_playing, settings, credits
    └── widgets/                  reusable Swiss control kit
```

Layering is strict: **screens never touch a datasource**. A Cubit talks to a repository, a repository talks to datasources, and playback is driven only through `PlayerCubit` → `PlaybackService`.

### The nine defensive laws

1. **Non-blocking startup** — every boot step is wrapped in a 4 s timeout. A dead network, disk, or audio device degrades one subsystem, not the app.
2. **A real foreground service** — background playback survives the UI being reclaimed; the notification is a real `MediaSession`.
3. **`IndexedStack` tabs** — scroll positions, queries, and queue views survive tab switches, and no tab rebuilds on navigation.
4. **A custom `ErrorWidget.builder`** — a failed widget paints a Swiss fault card with copy-report/dismiss instead of the red screen of death.
5. **Strict viewport constraints** — every screen works on wide and short viewports; nothing assumes a phone aspect ratio.
6. **FFI handle validation** — `_live(handle)` guards every SoLoud call.
7. **Null-safe JSON parsing** — one malformed catalogue row cannot poison a rail.
8. **State hydration on launch** — queue, position, likes, downloads, and settings are restored before the first paint.
9. **The fast path is never the only path** — every acceleration, probe, and progressive stream has a fallback that still plays.

---

## Build from source

**Prerequisites**

- Flutter **3.47.x** / Dart **3.13.x** or newer
- Android SDK with API 36
- JDK 17
- A device or emulator running Android 8.0+ (ARM64 or ARMv7)

```bash
git clone https://github.com/slok0066/Musify.git
cd Musify
flutter pub get

# Run on an Android device
flutter run -d <android-device-id>

# Static checks and the full test suite
flutter analyze
flutter test
```

**Release APKs**

```bash
flutter build apk --release --split-per-abi
```

The ARM artifacts land in `build/app/outputs/flutter-apk/`:

```text
app-arm64-v8a-release.apk
app-armeabi-v7a-release.apk
```

Flutter may also emit an `x86_64` artifact for emulators; Musify does not publish it. The checked-in Gradle configuration signs release builds with the local debug key so APKs are sideloadable. Replace it with your own keystore before distributing through a store.

---

## Verification

`flutter test` runs **84 tests** with no device, network, or audio engine attached:

- `jiosaavn_parsing_test.dart` — hostile catalogue payloads, the DES fixture, rotten Hive maps.
- `streaming_test.dart` — range splitting, container sniffing, error-page rejection, the rendition ladder.
- `mp4_aac_test.dart` — the MP4 sample table against a hand-built file, byte-exact ADTS assembly.
- `media_cache_stream_test.dart` — staged sessions, cache hits, unreachable-URL fallback.
- `artwork_url_test.dart` — artwork URL normalization and upgrade rules.
- `widget_test.dart` — theme tokens, keycap behavior, dock/navigation rules, formatting.
- `settings_credits_test.dart` — the first-install credits gate.

`flutter analyze` is clean. Release artifacts are checked from the file itself with `aapt` (version name/code, `minSdk` 26, `targetSdk` 36, ARM-only native libraries) and both published APK URLs are checked after the release goes live.

Two standalone proofs live in `tool/`:

- `tool/des_check.dart` — `encrypted_media_url` decryption and the `_96 → _320` upgrade.
- `tool/adts_check.dart` — frame-exact MP4 → ADTS output against a live 320 kbps file.

The detailed build journal — every compiler error, root cause, exact fix, and a symptom → cause → action index — is in [`docs/IMPLEMENTATION_LOG.md`](docs/IMPLEMENTATION_LOG.md).

---

## Updates and releases

The in-app updater reads [`version.json`](version.json) from `main` on GitHub. The manifest carries the version, build number, release notes, and the APK URL. Each request is cache-busted so a just-published release is visible immediately.

To ship a new build:

1. Bump `version` in `pubspec.yaml`, `kAppVersion`/`kAppBuild` in `lib/core/build_info.dart`, and `version.json`.
2. Run `flutter analyze` and `flutter test`.
3. Build with `flutter build apk --release --split-per-abi`.
4. Tag `vX.Y.Z`, attach both ARM APKs, and publish the GitHub release.
5. Point `version.json` at the new tag and commit it to `main`.

The app's build stamp must match the release: the version in the manifest, the version code in the APK, and the stamp in Settings are the three facts used to diagnose "am I running the fix?" reports.

---

## Project docs

| Document | Contents |
| --- | --- |
| [`docs/IMPLEMENTATION_LOG.md`](docs/IMPLEMENTATION_LOG.md) | Build journal, runtime-fault checklist, widget API cheat sheet, release notes for each version. |
| [`docs/UI_INVENTORY.md`](docs/UI_INVENTORY.md) | Screen-by-screen inventory of the interface. |
| [`docs/design/stitch/`](docs/design/stitch/) | Visual studies for Home, Library, Search, and Now Playing. |
| [`prd`](prd) | The original product requirements document. |

---

## Honest deviations

**The YouTube fallback was removed.** The PRD's resolver was JioSaavn → YouTube → Piped. In practice, public Piped instances answered with 525/502 throughout development, `youtube_explode_dart` search worked but stream extraction returned `VideoUnplayableException` (YouTube now requires a PO-token/attestation flow), and `saavn.dev` was dead. Shipping a fallback that silently fails would be worse than shipping the ladder that actually resolves.

The shipped resolver is JioSaavn's own web-player API at 320 → 160 → 96 kbps, then the direct URL, then the on-disk copy. The zero-paid-key requirement is fully satisfied: JioSaavn, LRCLIB, Deezer, and iTunes need no key.

**Smaller implementation notes**

- Fonts are bundled rather than fetched at runtime.
- Cache and download directories live under `getApplicationSupportDirectory()`.
- `pointycastle 4.x` has no single-DES engine, so the media-URL decryption uses `DESedeEngine` with the 8-byte key repeated three times — byte-for-byte identical to DES-ECB.
- The credits screen is gated by a launch marker plus persisted state, so it survives upgrades but appears only on a first install.

---

## Legal

Musify is a personal-use research and learning project. It streams from JioSaavn's public web endpoints and does not host, redistribute, or monetise any catalogue content. Music, artwork, lyrics, and trademarks belong to their respective owners. Endpoints can change, be rate-limited, or be geo-restricted; use the app at your own risk.
