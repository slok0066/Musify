/// Formatting helpers shared across the UI.
///
/// Everything the user reads as a number or a duration goes through here so the
/// instrument-panel voice stays consistent (zero-padded, monospace-friendly).
abstract final class Fmt {
  /// `03:28`, or `1:02:45` for long mixes. Always zero-padded on the left of
  /// the seconds field so the readout never jitters during playback.
  static String duration(Duration? d) {
    if (d == null || d <= Duration.zero) return '--:--';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${_p(minutes)}:${_p(seconds)}';
    }
    return '${_p(minutes)}:${_p(seconds)}';
  }

  /// `3:28` for rows and cards — no zero padding on minutes, keeps tables tidy.
  static String durationShort(Duration? d) {
    if (d == null || d <= Duration.zero) return '--:--';
    if (d.inHours > 0) {
      return '${d.inHours}:${_p(d.inMinutes.remainder(60))}:${_p(d.inSeconds.remainder(60))}';
    }
    return '${d.inMinutes}:${_p(d.inSeconds.remainder(60))}';
  }

  /// `2h 14m` — countdown for the sleep timer.
  static String countdown(Duration? d) {
    if (d == null) return '--:--';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) return '${_p(hours)}:${_p(minutes)}:${_p(seconds)}';
    return '${_p(minutes)}:${_p(seconds)}';
  }

  /// `142 MB`, `1.4 GB`.
  static String bytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const kb = 1024.0;
    if (bytes < kb * kb) return '${(bytes / kb).round()} KB';
    if (bytes < kb * kb * kb) {
      return '${(bytes / (kb * kb)).toStringAsFixed(bytes < kb * kb * 10 ? 1 : 0)} MB';
    }
    return '${(bytes / (kb * kb * kb)).toStringAsFixed(2)} GB';
  }

  /// `1,240,331` streams.
  static String compactCount(num? value) {
    if (value == null || value <= 0) return '—';
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  /// Monospace-friendly bitrate label: `320 KBPS`.
  static String bitrate(int? kbps) => kbps == null ? '—' : '$kbps KBPS';

  static String _p(int value) => value.toString().padLeft(2, '0');

  /// Removes HTML entities the JioSaavn payload leaves in titles
  /// (`&quot;`, `&amp;`, `&#039;`) and collapses whitespace.
  static String cleanTitle(String? raw) {
    if (raw == null || raw.isEmpty) return 'Unknown';
    var s = raw
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&hellip;', '…')
        .replaceAll('&nbsp;', ' ');

    // Some entries arrive still numeric-encoded, e.g. `&#8217;`.
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });

    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Artists arrive as one comma-joined subtitle. The first is the primary.
  static String primaryArtist(String? subtitle) {
    final clean = cleanTitle(subtitle);
    final first = clean.split(',').first.trim();
    return first.isEmpty ? 'Unknown' : first;
  }
}
