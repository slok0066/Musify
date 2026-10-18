// Artwork rendition helpers shared by the catalogue and the widgets.
//
// The catalogue only ever advertises its smallest cover; the JioSaavn CDN
// renders square renditions up to 500×500. Asking for the biggest rendition at
// *display* time too means a cover cached by an older build — or handed over by
// a fallback provider — cannot keep a large plate blurry forever.

/// Rewrites a `…-150x150.jpg` style URL to a larger rendition.
///
/// Only ever moves *up*: an image already at or above [size] — iTunes'
/// `600x600bb` and Deezer's `500x500-000000-80-0-0` shapes included — is left
/// untouched, because a guessed-up URL is a 404, and a 404 is a hole in the
/// layout. Returns `''` for an empty input, so callers can use it as the
/// "no artwork" check too.
String hiresArtwork(String url, {int size = 500}) {
  if (url.trim().isEmpty) return '';
  var clean = url.trim().replaceAll('http://', 'https://');
  clean = clean.replaceAllMapped(
    RegExp(r'(\d+)x(\d+)(\.(jpg|jpeg|png|webp))', caseSensitive: false),
    (match) {
      final current = int.tryParse(match.group(1) ?? '') ?? 0;
      if (current >= size) return match.group(0)!;
      return '${size}x$size${match.group(3)}';
    },
  );
  return clean;
}
