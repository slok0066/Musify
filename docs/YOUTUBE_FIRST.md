# YouTube as a second source — the working recipe

Removed from the app on 2026-11-13 (build **1.0.31+33**). Musify is JioSaavn-only
again. This file is the **only** copy of that implementation — it was never
committed, so `git log` cannot bring it back. Everything needed to rebuild it is
below.

All numbers and failures here were measured on a **Motorola Edge 60 Fusion**
(Android 17, arm64-v8a), Indian network, November 2026. Public endpoints rot:
treat host names as variables, the structure as the answer.

---

## 1. Shape of the feature

Three files, one hard switch, a handful of wiring lines:

```
lib/services/yt_first/
  yt_first_config.dart    constants + master switch   (39 lines)
  yt_first_search.dart    title parsing, candidate ranking (116 lines)
  youtube_service.dart    search + resolve + download  (443 lines)
```

Flow when `YtFirstConfig.enabled && settings.ytFirstEnabled`:

```
search(query)  → youtube_explode search → (empty) → Piped search
                 non-empty → return ONLY YouTube songs (no albums/artists/playlists)
                 empty     → normal Saavn search

play(track)    → staged file already on disk?  → play it (instant replay)
                 else direct youtube_explode (android client, 2 attempts)
                      → Invidious proxy (itag 140, then 139)
                      → Piped (1 attempt)
                      each candidate: fresh URL, UA of the client that signed it,
                      Range: bytes=0-, whole-body length check
                 all failed → Saavn match by title+artist
                 nothing    → "PLAYBACK ERROR", stay on screen (no auto-skip)
```

Result rows are marked `[YT]` / `[Saavn]` in Search when the feature is live.

---

## 2. Findings that save a day

| Thing | What actually happens |
|---|---|
| `youtube_explode_dart` client | `YoutubeApiClient.android` is the only one that resolves popular label uploads. `ios` and `androidVr` answer 403 or a sign-in prompt **after ~8 s**; `mweb`, `tv`, `androidSdkless` 403 immediately. |
| Direct googlevideo URLs | Work for ordinary uploads, **403 for label uploads** without a PO token. |
| Invidious | `https://yt.chocolatemoo53.com/latest_version?id=<id>&itag=<140\|139>&local=true` returned a working stream for every id tested, including label uploads. It proxies with a PO token, which is why it wins where direct clients lose. |
| Piped | All three public instances were dead: `pipedapi.kavin.rocks` 403/525, `pipedapi.leptons.xyz` 502, `pipedapi.adminforge.de` 301/404. Keep the code as a last resort, expect nothing. |
| Plain GET vs Range | A plain GET of a 3.3 MB file took **108 s** (~32 KB/s — YouTube throttles sequential reads). The identical file with `Range: bytes=0-` took **1.5 s**. The header is mandatory. |
| Download timeout | `dio`'s 8 s receive timeout aborted slow downloads mid-body and dropped playback to the Saavn match. The download needs its own **30 s** timeout. |
| Truncated bodies | A dropped connection ends the body early **without throwing**; the short MP4 plays a few seconds and stops. Compare the bytes on disk against `content-range`'s total (206) or `content-length` (200), and reject `text/html`. |
| Parallel lanes | 4 lanes through Invidious gave no gain: 2.78 MB in 2.4–4.7 s single vs 4.5–5.8 s on lanes, plus a probe round trip. Don't. |
| `local=false` (companion hosts) | Noisy 1.2–2× gain on some files, new failure mode. Not worth it. |
| Throughput | Invidious 0.7–1.9 MB/s. 20 MB (18 min mix) = 11–13 s. 50 MB (53 min mix) = 25 s+. Short songs (3 MB) start in 2–4 s. |
| Container | YouTube audio is **fragmented MP4**: `moov` ends at byte 723, there is no `stbl` sample table. `Mp4AacIndex` (Saavn's indexer) cannot index it, so the whole file must land before playback. This is the only real limitation left — see §6. |
| Replays | Short-circuit on the staged file (`_stagedFile`) before any resolve. Saves the 403 and the proxy round trip. |

---

## 3. Re-adding it

The removal touched these places. Restoring the feature means touching the same
ones; nothing else references YouTube.

### 3.1 Dependency

`pubspec.yaml`:

```yaml
  masko_player: ^0.1.17
  youtube_explode_dart: ^3.1.0
```

Then `flutter pub get`. It pulls `html`, `freezed_annotation`, `json_annotation`,
`archive`, `csslib`, `simple_sparse_list`, `unicode` as transitives — they leave
again when it does.

### 3.2 Model — `lib/data/models/track.dart`

Add the enum above the class:

```dart
/// Which catalogue produced a [Track]. Persisted, so entries written before
/// YouTube-first existed load as [saavn].
enum TrackSource { youtube, saavn }
```

Add the field and derived getters:

```dart
  /// Catalogue that produced this entry.
  final TrackSource source;

  bool get isYouTube => source == TrackSource.youtube;

  /// YouTube video id, encoded as `yt:<videoId>` in [id].
  String? get videoId {
    if (!isYouTube || !id.startsWith('yt:')) return null;
    final value = id.substring(3);
    return value.isEmpty ? null : value;
  }

  /// `[YT]` / `[Saavn]` search-row tag.
  String get sourceTag => isYouTube ? 'YT' : 'Saavn';
```

Constructor default `this.source = TrackSource.saavn,`; `copyWith` gets
`TrackSource? source` and `source: source ?? this.source`; `toMap` gets
`'source': source.name,`; `fromMap` gets:

```dart
      source: TrackSource.values.firstWhere(
        (s) => s.name == map['source']?.toString(),
        orElse: () => TrackSource.saavn,
      ),
```

and `props` gets `source`.

`fromMap` ignores the unknown `source` key the way it ignores any other field it
does not know, so there is no migration to undo. Rows saved by a YouTube build
load with `id: yt:...` and simply fail to resolve on Saavn; the player reports
`TRACK UNAVAILABLE — SKIPPING` and moves on.

### 3.3 Settings — `lib/services/settings_service.dart`

Field (defaults **on**), plus the same four boilerplate spots
(`copyWith` param, `copyWith` assignment, `toMap`, `fromMap`):

```dart
  /// YouTube-first test: search YouTube and use Saavn only when YouTube yields
  /// nothing. Off is exactly Saavn-only.
  final bool ytFirstEnabled;
```

```dart
    this.ytFirstEnabled = true,
    // copyWith:
    bool? ytFirstEnabled,
    // in copyWith body:
    ytFirstEnabled: ytFirstEnabled ?? this.ytFirstEnabled,
    // toMap:
    'ytFirstEnabled': ytFirstEnabled,
    // fromMap:
    ytFirstEnabled: boolAt('ytFirstEnabled', true),
```

`lib/presentation/cubits/settings_cubit.dart`:

```dart
  /// The const `YtFirstConfig.enabled` still gates this, so a build with the
  /// master switch off behaves as if it is false.
  void setYtFirst(bool enabled) =>
      _update(_settings.value.copyWith(ytFirstEnabled: enabled));
```

### 3.4 Repository — `lib/data/repositories/music_repository.dart`

Imports:

```dart
import '../../services/yt_first/yt_first_config.dart';
import '../../services/yt_first/youtube_service.dart';
```

Fields (lazy, so "off" means no socket at all):

```dart
  /// Constructed on first use: with YouTube-first off there is no client,
  /// no socket and no YouTube call.
  late final YoutubeService _youtube = YoutubeService();

  /// Effective switch: the const master switch and the persisted setting.
  bool get _ytFirst =>
      YtFirstConfig.enabled && _settings.value.ytFirstEnabled;
```

In `resolvePlayable`, between the offline check and the Saavn ladder:

```dart
    // YouTube resolves a fresh URL on every tap, never from a cache. A failed
    // stream retries once inside the service, then we match the same song on
    // Saavn. Prefetch is skipped: the next tap must resolve fresh.
    if (track.isYouTube) {
      if (prefetch) return null;
      if (_ytFirst) {
        final staged = await _youtube.stage(track, onProgress: onProgress);
        if (staged != null) {
          return PlayableSource(
            path: staged,
            isLocalFile: true,
            bitrate: track.bitrate,
          );
        }
      }
      final fallback = await _saavnMatchFor(track);
      if (fallback == null) return null;
      return resolvePlayable(fallback, onProgress: onProgress);
    }
```

Three more one-liners:

```dart
  // openStream(), first line — whole-file only, staged route takes over:
  if (track.isYouTube) return null;

  // prefetchTracks(), inside the loop:
  if (track.isYouTube) continue;

  // search(), before the Saavn Future.wait:
  if (_ytFirst) {
    final youtube = await _youtube.search(trimmed);
    if (youtube.isNotEmpty) {
      return SearchResults(
        query: trimmed,
        songs: Track.dedupe(youtube)
            .take(YtFirstConfig.maxSearchResults)
            .toList(),
      );
    }
  }
```

And the fallback matcher:

```dart
  /// Finds the same recording on Saavn after a YouTube playback failure.
  Future<Track?> _saavnMatchFor(Track track) async {
    try {
      final matches = await _saavn.searchSongs(
        '${track.title} ${track.artist}'.trim(),
        limit: 8,
      );
      if (matches.isEmpty) return null;
      for (final candidate in matches) {
        if (candidate.dedupeKey == track.dedupeKey) return candidate;
      }
      return matches.first;
    } catch (e) {
      debugPrint('yt-first: Saavn fallback failed for "${track.title}": $e');
      return null;
    }
  }
```

### 3.5 UI

`lib/presentation/screens/search/search_screen.dart` — import
`services/settings_service.dart` and `services/yt_first/yt_first_config.dart`,
then in `_ResultList` and `_TopResult`:

```dart
    final showSource = YtFirstConfig.enabled &&
        locator<SettingsService>().value.ytFirstEnabled;
```

```dart
    // TrackListTile:
    subtitle: showSource ? '[${track.sourceTag}] ${track.artist}' : null,
```

```dart
    // _TopResult artist line:
    showSource
        ? '[${track.sourceTag}] ${track.displayArtist}'
        : track.displayArtist,
```

`lib/presentation/screens/settings/settings_screen.dart` — import the config and
add the row after `INSTANT PLAY`:

```dart
                        if (YtFirstConfig.enabled)
                          SettingsToggleRow(
                            label: 'YOUTUBE FIRST',
                            hint: settings.ytFirstEnabled
                                ? 'SEARCH YOUTUBE, FALL BACK TO JIOSAAVN'
                                : 'SEARCH JIOSAAVN ONLY',
                            value: settings.ytFirstEnabled,
                            onChanged: cubit.setYtFirst,
                          ),
```

### 3.6 Player — `lib/services/player/playback_service.dart`

YouTube failures must stay on screen instead of auto-skipping, so the test can
see what broke:

```dart
      final source = await _resolveFor(track);
      if (source == null) {
        final youTube = track.isYouTube;
        errorText.value = youTube
            ? 'PLAYBACK ERROR'
            : 'TRACK UNAVAILABLE — SKIPPING';
        isBuffering.value = false;
        _bump();
        _switching = false;
        // A dead catalogue entry must not stall the queue. A YouTube failure
        // stays on screen so the test can see which source broke.
        if (!youTube) await _autoSkipAfterFailure();
        return;
      }
```

```dart
        errorText.value = track.isYouTube ? 'PLAYBACK ERROR' : 'PLAYBACK FAILED';
```

### 3.7 Test

`test/yt_first_test.dart`: keep it to the pure logic (the network paths need a
device). Cases worth locking in:

- `Track` with `source: youtube` survives `toMap`/`fromMap`; `sourceTag == 'YT'`;
  `videoId` is `dQw4w9WgXcQ` for id `yt:dQw4w9WgXcQ`.
- `YtTitles.parse('Kesariya - Arijit Singh (Official Video)', 'T-Series')`
  → `Kesariya` / `Arijit Singh`; `Song - Official Video` does not become an
  artist.
- `rankYtAudio` puts itag 140 first, AAC/MP4 above WebM.
- `ytFirstEnabled` defaults on and survives JSON.
- Removing the `fromMap` legacy guard must not break these.

---

## 4. Full source

Copy these three files to `lib/services/yt_first/`. They compile as-is against
the wiring in §3.

### `lib/services/yt_first/yt_first_config.dart`

```dart
/// Master switch for the YouTube-first test.
///
/// Set [enabled] to `false` (or delete this folder plus the few wiring lines in
/// `MusicRepository`, `PlaybackService` and Settings) to return to Saavn-only:
/// no Piped call, no YouTube search, no YouTube resolve.
class YtFirstConfig {
  const YtFirstConfig._();

  /// Hard kill switch. The Settings toggle can only narrow this, never widen it.
  static const bool enabled = true;

  /// Per-request timeout. `youtube_explode_dart` resolves first; Piped is the
  /// fallback instance list.
  static const Duration requestTimeout = Duration(seconds: 8);

  /// Idle timeout for the audio download itself. A 20 MB mix over a flaky
  /// link can pause for more than [requestTimeout] between chunks; aborting
  /// there is what dropped playback to the Saavn match.
  static const Duration downloadTimeout = Duration(seconds: 30);

  /// Public Piped API instances, tried in order.
  static const List<String> pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.leptons.xyz',
    'https://pipedapi.adminforge.de',
  ];

  /// Invidious proxies the stream with a PO token, so label uploads that
  /// return 403 to direct clients still play. Tried after the direct clients.
  static const String invidiousInstance = 'https://yt.chocolatemoo53.com';

  /// Piped is a web API, so its calls use a browser UA.
  static const String browserUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Keep the list below the search screen's 25-result pagination threshold so
  /// a YouTube list never triggers Saavn page 2.
  static const int maxSearchResults = 20;
}
```

### `lib/services/yt_first/yt_first_search.dart`

```dart
import '../../core/utils/formatters.dart';

/// A YouTube title split into the app's title + primary artist fields.
class ParsedYtTitle {
  const ParsedYtTitle({required this.title, required this.artist});

  final String title;
  final String artist;
}

/// Best-effort normalisation of YouTube video titles:
/// `Kesariya - Arijit Singh (Official Video)` -> `Kesariya` / `Arijit Singh`.
class YtTitles {
  const YtTitles._();

  static final RegExp _noiseGroup = RegExp(
    r'[\(\[](?:[^\)\]]*\b(?:official|lyrics?|audio|video|visuali[sz]er|full song|remaster(?:ed)?|hd|4k|8k)\b[^\)\]]*)[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _separator = RegExp(r'\s+[-–—|]\s+');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _edgePunctuation = RegExp(r'^[\s\-–—|]+|[\s\-–—|]+$');
  static final RegExp _noiseStart = RegExp(
    r'^(?:official|lyrics?|audio|video|music|full song|visuali[sz]er|remaster)',
    caseSensitive: false,
  );

  static ParsedYtTitle parse(String rawTitle, String fallbackArtist) {
    final original = _tidy(rawTitle);
    final uploader = _tidy(fallbackArtist);

    var title = _tidy(original.replaceAll(_noiseGroup, ' '));
    var artist = '';

    final parts = title.split(_separator);
    if (parts.length == 2) {
      final left = _tidy(parts[0]);
      final right = _tidy(parts[1]);
      if (left.isNotEmpty && right.isNotEmpty) {
        if (_noiseStart.hasMatch(right)) {
          // `Song - Official Video`: the right side is not an artist.
          title = left;
        } else if (_noiseStart.hasMatch(left)) {
          // `Official Video - Song`: the left side is not a title.
          title = right;
        } else {
          title = left;
          artist = right;
        }
      }
    }

    if (title.isEmpty) title = original.isEmpty ? 'Unknown' : original;
    if (artist.isEmpty) artist = uploader.isEmpty ? 'Unknown' : uploader;
    return ParsedYtTitle(title: title, artist: artist);
  }

  static String _tidy(String raw) {
    if (raw.trim().isEmpty) return '';
    return Fmt.cleanTitle(raw)
        .replaceAll(_edgePunctuation, '')
        .replaceAll(_spaces, ' ')
        .trim();
  }
}

enum YtContainer { mp4, webm, other }

/// One audio URL from either resolver, carrying the UA that obtained it.
class YtAudioCandidate {
  const YtAudioCandidate({
    required this.itag,
    required this.container,
    required this.codec,
    required this.bitrateKbps,
    required this.url,
    required this.userAgent,
    required this.source,
  });

  final int itag;
  final YtContainer container;
  final String codec;
  final int bitrateKbps;
  final String url;
  final String userAgent;

  /// `piped` or `youtube_explode_<client>`; only used in failure logs.
  final String source;

  bool get isMp4 => container == YtContainer.mp4;

  bool get isAacMp4 {
    final c = codec.toLowerCase();
    return isMp4 && (c.contains('mp4a') || c.contains('aac'));
  }
}

/// AAC/MP4 first (itag 140 ahead of every other stream), then any MP4, then
/// WebM; highest bitrate first inside each group.
List<YtAudioCandidate> rankYtAudio(Iterable<YtAudioCandidate> input) {
  final out = input.toList()
    ..sort((a, b) {
      final byContainer = _score(b) - _score(a);
      if (byContainer != 0) return byContainer;
      return b.bitrateKbps.compareTo(a.bitrateKbps);
    });
  return out;
}

int _score(YtAudioCandidate candidate) {
  if (candidate.itag == 140) return 3;
  if (candidate.isAacMp4) return 2;
  if (candidate.isMp4) return 1;
  return 0;
}
```

### `lib/services/yt_first/youtube_service.dart`

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../data/models/track.dart';
import 'yt_first_config.dart';
import 'yt_first_search.dart';

/// YouTube as the primary source for the `test-yt-first` branch.
///
/// Search and playback go `youtube_explode_dart` first (its Android client
/// resolves label uploads), then Invidious, then Piped. Playback resolves a
/// fresh URL on every tap, ranks AAC/MP4 ahead of WebM, and downloads one whole
/// file into a temp folder with the UA of the client that signed the URL.
/// YouTube serves fragmented MP4, which the progressive AAC reader cannot
/// index, so there is nothing to stream — the whole file has to land first.
/// Nothing here caches a URL.
class YoutubeService {
  YoutubeService({Dio? dio, YoutubeExplode? explorer})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: YtFirstConfig.requestTimeout,
                receiveTimeout: YtFirstConfig.requestTimeout,
                sendTimeout: YtFirstConfig.requestTimeout,
                headers: {'user-agent': YtFirstConfig.browserUserAgent},
              ),
            ),
        _explorer = explorer;

  final Dio _dio;
  YoutubeExplode? _explorer;

  YoutubeExplode get _yt => _explorer ??= YoutubeExplode();

  /// YouTube results, or an empty list when every YouTube path failed.
  Future<List<Track>> search(String query) async {
    final explode = await _explodeSearch(query);
    if (explode.isNotEmpty) return explode;
    return _pipedSearch(query);
  }

  /// Downloads the best playable audio for [track] and returns its local path.
  ///
  /// Returns `null` when both stream candidates and the resolve failed; the
  /// repository then tries the Saavn match.
  Future<String?> stage(
    Track track, {
    ValueChanged<double?>? onProgress,
  }) async {
    final videoId = track.videoId;
    if (videoId == null) return null;

    // A finished staging is already playable: skip the resolve, its 403 and
    // the proxy round trip entirely. This is what makes a replay instant.
    final cached = await _stagedFile(videoId);
    if (cached != null) return cached;

    final staged = await _stageFirst(
      track,
      await _explodeCandidates(videoId),
      maxAttempts: 2,
      onProgress: onProgress,
    );
    if (staged != null) return staged;

    final proxied = await _stageFirst(
      track,
      _invidiousCandidates(videoId),
      maxAttempts: 1,
      onProgress: onProgress,
    );
    if (proxied != null) return proxied;

    final piped = await _stageFirst(
      track,
      await _pipedCandidates(videoId),
      maxAttempts: 1,
      onProgress: onProgress,
    );
    if (piped != null) return piped;

    debugPrint(
      'yt-first playback FAIL source=none title="${track.title}" '
      'host=- error=no playable stream',
    );
    return null;
  }

  Future<String?> _stageFirst(
    Track track,
    List<YtAudioCandidate> candidates, {
    required int maxAttempts,
    ValueChanged<double?>? onProgress,
  }) async {
    var attempts = 0;
    for (final candidate in rankYtAudio(candidates)) {
      if (attempts == maxAttempts) break;
      attempts++;
      final path = await _download(track, candidate, onProgress: onProgress);
      if (path != null) return path;
    }
    return null;
  }

  Future<List<Track>> _pipedSearch(String query) async {
    for (final base in YtFirstConfig.pipedInstances) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '$base/search',
          queryParameters: {'q': query, 'filter': 'music_songs'},
        );
        final items = response.data?['items'];
        if (items is! List) continue;

        final out = <Track>[];
        final seen = <String>{};
        for (final raw in items) {
          if (raw is! Map) continue;
          final item = raw.cast<Object?, Object?>();
          final videoId = _videoIdFromUrl(item['url']?.toString());
          if (videoId == null) continue;
          final seconds = _int(item['duration']);
          if (seconds <= 0) continue;

          final track = _track(
            videoId: videoId,
            title: item['title']?.toString() ?? '',
            uploader: item['uploaderName']?.toString() ?? '',
            duration: Duration(seconds: seconds),
            thumbnail: item['thumbnail']?.toString() ?? '',
          );
          if (seen.add(track.dedupeKey)) out.add(track);
          if (out.length >= YtFirstConfig.maxSearchResults) break;
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        debugPrint('yt-first: Piped search failed on $base: $e');
      }
    }
    return const [];
  }

  Future<List<Track>> _explodeSearch(String query) async {
    try {
      final videos = await _yt.search
          .search(query, filter: TypeFilters.video)
          .timeout(YtFirstConfig.requestTimeout);

      final out = <Track>[];
      final seen = <String>{};
      for (final video in videos) {
        if (video.isLive) continue;
        final track = _track(
          videoId: video.id.value,
          title: video.title,
          uploader: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnail: video.thumbnails.mediumResUrl,
        );
        if (seen.add(track.dedupeKey)) out.add(track);
        if (out.length >= YtFirstConfig.maxSearchResults) break;
      }
      return out;
    } catch (e) {
      debugPrint('yt-first: YouTube search fallback failed: $e');
      return const [];
    }
  }

  Track _track({
    required String videoId,
    required String title,
    required String uploader,
    required Duration duration,
    required String thumbnail,
  }) {
    final parsed = YtTitles.parse(title, uploader);
    return Track(
      id: 'yt:$videoId',
      title: parsed.title,
      artist: parsed.artist,
      imageUrl: thumbnail,
      duration: duration,
      bitrate: 128,
      has320: false,
      permaUrl: 'https://www.youtube.com/watch?v=$videoId',
      source: TrackSource.youtube,
    );
  }

  Future<List<YtAudioCandidate>> _pipedCandidates(String videoId) async {
    for (final base in YtFirstConfig.pipedInstances) {
      try {
        final response =
            await _dio.get<Map<String, dynamic>>('$base/streams/$videoId');
        final data = response.data;
        if (data == null || data['error'] != null) continue;

        final streams = data['audioStreams'];
        if (streams is! List) continue;

        final out = <YtAudioCandidate>[];
        for (final raw in streams) {
          if (raw is! Map) continue;
          final stream = raw.cast<Object?, Object?>();
          final url = stream['url']?.toString() ?? '';
          if (!url.startsWith('http')) continue;

          final mime = stream['mimeType']?.toString() ??
              stream['format']?.toString() ??
              '';
          final codec = stream['codec']?.toString() ?? '';
          out.add(
            YtAudioCandidate(
              itag: _int(stream['itag']),
              container: _containerFor(mime.isEmpty ? codec : mime),
              codec: codec.isEmpty ? mime : codec,
              bitrateKbps: _int(stream['bitrate']),
              url: url,
              userAgent: YtFirstConfig.browserUserAgent,
              source: 'piped',
            ),
          );
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        debugPrint('yt-first: Piped streams failed on $base: $e');
      }
    }
    return const [];
  }

  /// The Invidious proxy's `/latest_version` redirects to a stream signed with
  /// a PO token; direct clients get 403 on label uploads without one.
  List<YtAudioCandidate> _invidiousCandidates(String videoId) {
    return [
      for (final entry in const {140: 128, 139: 48}.entries)
        YtAudioCandidate(
          itag: entry.key,
          container: YtContainer.mp4,
          codec: 'mp4a',
          bitrateKbps: entry.value,
          url: '${YtFirstConfig.invidiousInstance}/latest_version'
              '?id=$videoId&itag=${entry.key}&local=true',
          userAgent: YtFirstConfig.browserUserAgent,
          source: 'invidious',
        ),
    ];
  }

  /// `android` is the only client that resolves popular label uploads; `ios`
  /// and `androidVr` answer 403 or a sign-in prompt after several seconds, so
  /// Invidious takes over instead of paying for that timeout.
  Future<List<YtAudioCandidate>> _explodeCandidates(String videoId) async {
    const client = YoutubeApiClient.android;
    try {
      final manifest = await _yt.videos.streams
          .getManifest(videoId, ytClients: [client])
          .timeout(YtFirstConfig.requestTimeout);
      final ua = _userAgent(client);
      return [
        for (final stream in manifest.audioOnly)
          YtAudioCandidate(
            itag: stream.tag,
            container: _containerFor(stream.container.name),
            codec: stream.audioCodec,
            bitrateKbps: stream.bitrate.kiloBitsPerSecond.round(),
            url: stream.url.toString(),
            userAgent: ua,
            source: 'youtube_explode_${_clientName(client)}',
          ),
      ];
    } catch (e) {
      debugPrint(
        'yt-first: YouTube streams failed with ${_clientName(client)}: $e',
      );
      return const [];
    }
  }

  Future<String?> _download(
    Track track,
    YtAudioCandidate candidate, {
    ValueChanged<double?>? onProgress,
  }) async {
    final host = Uri.tryParse(candidate.url)?.host ?? 'unknown';
    final extension = candidate.container == YtContainer.webm ? 'webm' : 'm4a';
    final watch = Stopwatch()..start();
    File? part;
    try {
      final dir = await _stagingDir();
      final target = File(
        '${dir.path}${Platform.pathSeparator}'
        'yt_${track.videoId}_${candidate.itag}.$extension',
      );
      if (target.existsSync() && await target.length() > 0) return target.path;

      part = File('${target.path}.part');
      if (part.existsSync()) await part.delete();

      final response = await _dio.download(
        candidate.url,
        part.path,
        deleteOnError: true,
        options: Options(headers: {
          'user-agent': candidate.userAgent,
          // YouTube throttles a full GET to ~32 KB/s; a range request is not
          // throttled and fetches the same whole file at full speed.
          'range': 'bytes=0-',
        }, receiveTimeout: YtFirstConfig.downloadTimeout),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      // A dropped connection ends the body early without throwing, and the
      // short MP4 then plays a few seconds and stops. Only a body of the
      // promised size, and never an HTML error page, may be handed on.
      final length = await part.length();
      final declared = _declaredBytes(response.headers);
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      if (type.contains('text/html')) {
        throw FormatException('error page instead of audio ($length bytes)');
      }
      if (length == 0 || (declared != null && length != declared)) {
        throw FormatException('body is $length of ${declared ?? '?'} bytes');
      }

      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
      debugPrint(
        'yt-first playback OK source=${candidate.source} '
        'title="${track.title}" itag=${candidate.itag} '
        'bytes=$length ms=${watch.elapsedMilliseconds}',
      );
      return target.path;
    } catch (e) {
      debugPrint(
        'yt-first playback FAIL source=${candidate.source} '
        'title="${track.title}" host=$host itag=${candidate.itag} error=$e',
      );
      try {
        if (part != null && part.existsSync()) await part.delete();
      } catch (_) {}
      return null;
    }
  }

  /// A previous staging of [videoId] that is still in the temp folder.
  Future<String?> _stagedFile(String videoId) async {
    final dir = await _stagingDir();
    for (final itag in const [140, 139]) {
      final file = File(
        '${dir.path}${Platform.pathSeparator}yt_${videoId}_$itag.m4a',
      );
      if (file.existsSync() && await file.length() > 0) return file.path;
    }
    return null;
  }

  /// Where staged audio lands.
  // shortcut: this is the OS cache folder, which the system may clear but this
  // app never prunes; add age-based cleanup if the test becomes permanent.
  Future<Directory> _stagingDir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}musify_yt');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// The whole-file size the response promised: a 206 totals it in
  /// `content-range`, a plain 200 in `content-length`.
  static int? _declaredBytes(Headers headers) {
    final range = headers.value('content-range');
    if (range != null) {
      final slash = range.lastIndexOf('/');
      final total = slash < 0 ? null : int.tryParse(range.substring(slash + 1));
      if (total != null && total > 0) return total;
    }
    final length = int.tryParse(headers.value('content-length') ?? '');
    return length != null && length > 0 ? length : null;
  }

  static String _clientName(YoutubeApiClient client) {
    final context = client.payload['context'];
    if (context is Map) {
      final name = context['client'];
      if (name is Map) return name['clientName']?.toString() ?? 'unknown';
    }
    return 'unknown';
  }

  static String _userAgent(YoutubeApiClient client) {
    final context = client.payload['context'];
    if (context is Map) {
      final c = context['client'];
      if (c is Map) {
        final ua = c['userAgent'];
        if (ua is String && ua.isNotEmpty) return ua;
      }
    }
    return YtFirstConfig.browserUserAgent;
  }

  static YtContainer _containerFor(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('mp4') ||
        value.contains('m4a') ||
        value.contains('aac')) {
      return YtContainer.mp4;
    }
    if (value.contains('webm') ||
        value.contains('opus') ||
        value.contains('vorbis')) {
      return YtContainer.webm;
    }
    return YtContainer.other;
  }

  static String? _videoIdFromUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(
      raw.startsWith('http') ? raw : 'https://www.youtube.com$raw',
    );
    if (uri == null) return null;
    final fromQuery = uri.queryParameters['v'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return null;
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
```

---

## 5. Don't retry these

- **Other YouTube clients** (`ios`, `androidVr`, `mweb`, `tv`, `androidSdkless`)
  for label uploads — 403 or an 8-second sign-in prompt. Only `android`.
- **A plain GET** without `Range: bytes=0-` — 32 KB/s, ~100 s for a song.
- **Parallel range lanes** for the download — measured, no gain.
- **Invidious `local=false`** (companion hosts) — noisy, new failure mode.
- **Streaming the staged file** through the existing progressive path — the
  fMP4 has no `stbl`, `Mp4AacIndex` returns null.
- **Piped as a primary** — every public instance was dead.
- **Storing resolved URLs** — they expire in minutes; always resolve on tap.

--

## 6. The fix it still needs: instant start

The one thing that was never solved: a long mix waits for the whole file
(20 MB ≈ 11–13 s, 50 MB ≈ 25 s+). Short songs are fine (2–4 s).

YouTube's fMP4 is already chunk-friendly — each `moof` carries `trun` sample
sizes — so playback can start after ~200 KB. Options, cheapest first:

1. **Engine-side sequential mode.** Teach `Mp4AacIndex` (or its caller) to walk
   `moof`/`trun` as the file grows and emit sample runs; open the staged file
   with `duration = unknown`, no seek table until the last box lands. ~40–60
   lines in the existing box walker. Reuses the download path unchanged.
2. **Raw-frame mode on the pull-buffer.** If the native decoder is
   MediaCodec/FFmpeg it already eats raw AAC once it has the `esds` config: feed
   `(size, bytes)` pairs from `trun` instead of boxing every frame in ADTS.
   Less copying, fewer header bugs.
3. **Let the engine take the URL.** A native `setSource(url)`; MediaExtractor /
   FFmpeg demux fMP4 over HTTP natively, so the Dart download disappears.
   Only works if the native layer already wraps one of those.

All three still have to read `trun` — that is unavoidable — but inside the
engine it is a box walk that mostly exists already, not a second download path.

---

## 7. Removal checklist (what was deleted in 1.0.31+33)

Use this to verify a full removal, or as the inverse of §3.

- `lib/services/yt_first/` — all three files in §4.
- `test/yt_first_test.dart`.
- `Track`: `TrackSource`, `source`, `isYouTube`, `videoId`, `sourceTag`,
  `toMap`/`fromMap`/`props`/`copyWith` support. Persisted rows from a YouTube
  build are left alone and fall back to Saavn resolution.
- `MusicRepository`: two imports, `_youtube`, `_ytFirst`, the `resolvePlayable`
  branch, the `openStream` and `prefetchTracks` guards, the `search` block,
  `_saavnMatchFor`.
- `MusifySettings`: `ytFirstEnabled` + its four boilerplate spots.
- `SettingsCubit.setYtFirst`.
- `SettingsScreen`: the `YOUTUBE FIRST` row + config import.
- `SearchScreen`: `showSource` in `_ResultList` and `_TopResult`, the `[tag]`
  subtitles, the settings/config imports.
- `PlaybackService`: the `PLAYBACK ERROR` branch and its no-auto-skip behaviour.
- `pubspec.yaml`: `youtube_explode_dart` (removes `html`, `freezed_annotation`,
  `json_annotation`, `archive`, `csslib`, `simple_sparse_list`, `unicode`).
