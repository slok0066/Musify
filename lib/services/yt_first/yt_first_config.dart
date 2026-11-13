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

