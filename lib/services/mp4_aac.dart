import 'dart:typed_data';

/// The AAC audio inside a progressive MP4 file, indexed for byte-range reading.
///
/// ## Why this exists
/// `flutter_soloud` cannot stream MP4/M4A: the platform decoder for those
/// containers is `MediaExtractor` + `MediaCodec`, which decodes the **entire**
/// file to PCM at load time. A 10 MB, 4½-minute JioSaavn track therefore costs
/// its download *plus* a full AAC decode before the first sample is audible.
///
/// The engine *can* stream plain AAC, though: `setPullBufferStream` with
/// `BufferType.auto` feeds an ADTS elementary stream to a decoder that runs on
/// demand. So Musify reads the MP4's sample table (`moov`), wraps each raw AAC
/// frame in a 7-byte ADTS header, and hands the engine frames as they are
/// needed. Playback then starts after ~200 KB instead of ~10 MB, and there is no
/// full-file PCM decode at all.
///
/// ## What is parsed
/// `moov` ▸ `trak` (`hdlr` == `soun`) ▸ `mdia` ▸ `minf` ▸ `stbl`:
/// `stsd` (codec config: channels, sample rate, AudioSpecificConfig),
/// `stsz` (frame sizes), `stsc` (frames per chunk), `stco`/`co64` (chunk
/// offsets) and `stts` (frame durations). Fragmented files (`moof`) are
/// rejected, and every failure returns `null` so the caller can fall back to
/// the classic download path (PRD Law 8: never throw at the engine).
class Mp4AacIndex {
  Mp4AacIndex._({
    required Uint32List sampleOffsets,
    required Uint32List sampleSizes,
    required Uint32List adtsStarts,
    required this.sampleRate,
    required this.channels,
    required this.srIndex,
    required this.channelConfig,
    required this.samplesPerFrame,
    required this.duration,
  })  : _sampleOffsets = sampleOffsets,
        _sampleSizes = sampleSizes,
        _adtsStarts = adtsStarts;

  /// Bytes added in front of every raw AAC frame.
  static const int adtsHeaderBytes = 7;

  /// ADTS carries AAC-LC as profile 1; anything else is rejected rather than
  /// mis-declared.
  static const int profile = 1;

  /// Sample entry types that mean "AAC in this stsd".
  static const Set<String> _audioEntryTypes = {'mp4a', 'aac '};

  final Uint32List _sampleOffsets;
  final Uint32List _sampleSizes;

  /// `_adtsStarts[i]` is the byte offset of frame `i` inside the ADTS stream;
  /// `_adtsStarts[sampleCount]` is therefore the stream's total length.
  final Uint32List _adtsStarts;

  final int sampleRate;
  final int channels;
  final int srIndex;
  final int channelConfig;
  final int samplesPerFrame;
  final Duration duration;

  int get sampleCount => _sampleSizes.length;

  /// Total size of the assembled ADTS elementary stream.
  int get totalAdtsBytes => _adtsStarts[sampleCount];

  int get totalFileBytes => _sampleOffsets[sampleCount - 1] + _sampleSizes[sampleCount - 1];

  // ---------------------------------------------------------------- parsing

  /// Parses a byte window that contains a complete `moov` box.
  ///
  /// The window may be the head of the file (faststart) or its tail (`moov`
  /// written after `mdat`); `stco` offsets are absolute either way, so both
  /// layouts work. Returns `null` for anything unsupported or inconsistent.
  static Mp4AacIndex? parse(Uint8List window, {int? fileLength}) {
    if (window.length < 40) return null;
    try {
      final top = _boxes(window, 0, window.length);
      if (top.isEmpty) return null;
      // Fragmented MP4 has no `stbl` sample table: not supported, fall back.
      if (top.any((b) => b.type == 'moof')) return null;

      final moov = _first(top, 'moov');
      if (moov == null || moov.truncated) return null;

      for (final trak in _boxes(window, moov.payload, moov.end)) {
        if (trak.type != 'trak') continue;
        final parsed = _fromTrak(window, trak, fileLength);
        if (parsed != null) return parsed;
      }
      return null;
    } catch (_) {
      // A malformed table is a reason to use the classic path, never to crash.
      return null;
    }
  }

  static Mp4AacIndex? _fromTrak(Uint8List d, _Box trak, int? fileLength) {
    final mdia = _first(_boxes(d, trak.payload, trak.end), 'mdia');
    if (mdia == null) return null;

    final mdiaBoxes = _boxes(d, mdia.payload, mdia.end);
    final hdlr = _first(mdiaBoxes, 'hdlr');
    if (hdlr != null && hdlr.end - hdlr.payload >= 12) {
      // hdlr: version/flags(4) pre_defined(4) handler_type(4).
      if (_ascii(d, hdlr.payload + 8, 4) != 'soun') return null;
    }

    final minf = _first(mdiaBoxes, 'minf');
    if (minf == null) return null;
    final stbl = _first(_boxes(d, minf.payload, minf.end), 'stbl');
    if (stbl == null) return null;
    final stblBoxes = _boxes(d, stbl.payload, stbl.end);

    // --- codec configuration -------------------------------------------
    final stsd = _first(stblBoxes, 'stsd');
    if (stsd == null || stsd.end - stsd.payload < 16) return null;
    // stsd payload: version/flags(4) entry_count(4) then sample entries.
    final entries = _boxes(d, stsd.payload + 8, stsd.end);
    if (entries.isEmpty) return null;
    final entry = entries.first;
    if (!_audioEntryTypes.contains(entry.type)) return null;
    if (entry.end - entry.payload < 28) return null;

    // AudioSampleEntry: reserved(6) dri(2) reserved[2](8)
    //                   channelcount(2) samplesize(2) pre_defined(2) reserved(2)
    //                   samplerate(4, 16.16) then child boxes.
    final channels = _u16(d, entry.payload + 16);
    final sampleRate = _u32(d, entry.payload + 24) >> 16;
    if (channels < 1 || channels > 8 || sampleRate < 8000 || sampleRate > 192000) {
      return null;
    }

    final esds = _first(_boxes(d, entry.payload + 28, entry.end), 'esds');
    if (esds == null) return null;
    // esds payload: version/flags(4) then the MPEG-4 descriptor tree.
    final asc = _readAsc(d, esds.payload + 4, esds.end);
    if (asc == null || asc.length < 2) return null;

    final aot = asc[0] >> 3;
    if (aot != 2) return null; // AAC-LC only.
    final srIndex = ((asc[0] & 0x07) << 1) | (asc[1] >> 7);
    final channelConfig = (asc[1] >> 3) & 0x0F;
    if (srIndex > 12 || channelConfig == 0 || channelConfig > 7) return null;

    // --- sample table ---------------------------------------------------
    final stsz = _first(stblBoxes, 'stsz');
    final stsc = _first(stblBoxes, 'stsc');
    final stts = _first(stblBoxes, 'stts');
    final stco = _first(stblBoxes, 'stco') ?? _first(stblBoxes, 'co64');
    if (stsz == null || stsc == null || stco == null || stts == null) return null;

    final sampleCount = _u32(d, stsz.payload + 8);
    if (sampleCount <= 0 || sampleCount > (1 << 22)) return null;

    final sizes = Uint32List(sampleCount);
    final fixedSize = _u32(d, stsz.payload + 4);
    if (fixedSize > 0) {
      sizes.fillRange(0, sampleCount, fixedSize);
    } else {
      if (stsz.payload + 12 + 4 * sampleCount > stsz.end) return null;
      for (var i = 0; i < sampleCount; i++) {
        sizes[i] = _u32(d, stsz.payload + 12 + 4 * i);
      }
    }

    final chunkCount = _u32(d, stco.payload + 4);
    if (chunkCount <= 0) return null;
    final runCount = _u32(d, stsc.payload + 4);
    if (runCount <= 0) return null;
    final wideChunks = stco.type == 'co64';

    int chunkOffset(int index) {
      final at = stco.payload + 8 + (wideChunks ? index * 8 : index * 4);
      return wideChunks ? _u64(d, at) : _u32(d, at);
    }

    final offsets = Uint32List(sampleCount);
    var placed = 0;
    for (var run = 0; run < runCount && placed < sampleCount; run++) {
      final at = stsc.payload + 8 + run * 12;
      if (at + 12 > stsc.end) return null;
      final firstChunk = _u32(d, at);
      final perChunk = _u32(d, at + 4);
      final nextAt = at + 12;
      final nextFirstChunk =
          (run + 1 < runCount && nextAt + 12 <= stsc.end) ? _u32(d, nextAt) : chunkCount + 1;
      if (perChunk == 0 || firstChunk == 0) return null;

      for (var chunk = firstChunk;
          chunk < nextFirstChunk && chunk <= chunkCount && placed < sampleCount;
          chunk++) {
        var offset = chunkOffset(chunk - 1);
        for (var inChunk = 0; inChunk < perChunk && placed < sampleCount; inChunk++) {
          offsets[placed] = offset;
          offset += sizes[placed];
          placed++;
        }
      }
    }
    if (placed != sampleCount) return null;

    // --- timing ---------------------------------------------------------
    var ticks = 0;
    var firstDelta = 0;
    final sttsEntries = _u32(d, stts.payload + 4);
    for (var i = 0; i < sttsEntries; i++) {
      final at = stts.payload + 8 + i * 8;
      if (at + 8 > stts.end) break;
      final count = _u32(d, at);
      final delta = _u32(d, at + 4);
      if (i == 0) firstDelta = delta;
      ticks += count * delta;
    }
    final samplesPerFrame = (firstDelta > 0 && firstDelta <= 8192) ? firstDelta : 1024;
    final micros = ticks > 0
        ? (ticks * 1000000 / sampleRate).round()
        : (sampleCount * samplesPerFrame * 1000000 / sampleRate).round();

    // --- ADTS prefix sums ----------------------------------------------
    final starts = Uint32List(sampleCount + 1);
    var cursor = 0;
    for (var i = 0; i < sampleCount; i++) {
      starts[i] = cursor;
      cursor += adtsHeaderBytes + sizes[i];
    }
    starts[sampleCount] = cursor;

    // A sample pointing past the end of the file means a corrupt index.
    if (fileLength != null) {
      final last = offsets[sampleCount - 1] + sizes[sampleCount - 1];
      if (last > fileLength) return null;
    }

    return Mp4AacIndex._(
      sampleOffsets: offsets,
      sampleSizes: sizes,
      adtsStarts: starts,
      sampleRate: sampleRate,
      channels: channels,
      srIndex: srIndex,
      channelConfig: channelConfig,
      samplesPerFrame: samplesPerFrame,
      duration: Duration(microseconds: micros),
    );
  }

  // ---------------------------------------------------------------- reading

  /// Parses a window that may start in the middle of a file, locating `moov` by
  /// its box signature.
  ///
  /// `moov` is normally the second box in the file (faststart), which [parse]
  /// handles. When a muxer wrote it last, the tail of the file plus a byte scan
  /// is the only way to the sample table — and worth every cycle, because the
  /// alternative is decoding ten megabytes to find out how long the track is.
  static Mp4AacIndex? parseAnywhere(Uint8List window, {int? fileLength}) {
    final direct = parse(window, fileLength: fileLength);
    if (direct != null) return direct;
    if (window.length < 16) return null;

    for (var at = 0; at + 8 <= window.length; at++) {
      // 'm' 'o' 'o' 'v', preceded by a size we do not need to trust.
      if (window[at + 4] != 0x6D ||
          window[at + 5] != 0x6F ||
          window[at + 6] != 0x6F ||
          window[at + 7] != 0x76) {
        continue;
      }
      final candidate = parse(
        Uint8List.sublistView(window, at),
        fileLength: fileLength,
      );
      if (candidate != null) return candidate;
    }
    return null;
  }

  /// The frame that contains ADTS byte [adtsOffset] (clamped into range).
  int sampleAt(int adtsOffset) {
    if (adtsOffset <= 0) return 0;
    if (adtsOffset >= totalAdtsBytes) return sampleCount - 1;
    var lo = 0;
    var hi = sampleCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_adtsStarts[mid] <= adtsOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// A read window covering at least [maxBytes] of ADTS stream from
  /// [adtsOffset], aligned to frame boundaries.
  ///
  /// [fileStart]..[fileEnd] is the raw file range the frames live in; because
  /// the sample table is ordered, that is a single contiguous range.
  AacWindow windowAt(int adtsOffset, int maxBytes) {
    final first = sampleAt(adtsOffset);
    final from = _adtsStarts[first];
    final target = from + (maxBytes < adtsHeaderBytes ? adtsHeaderBytes : maxBytes);
    var last = first;
    while (last + 1 < sampleCount && _adtsStarts[last + 1] < target) {
      last++;
    }
    return AacWindow(
      adtsOffset: from,
      firstSample: first,
      lastSample: last,
      fileStart: _sampleOffsets[first],
      fileEnd: _sampleOffsets[last] + _sampleSizes[last],
      adtsBytes: _adtsStarts[last + 1] - from,
    );
  }

  /// Wraps the raw frames of [window] in ADTS headers.
  ///
  /// [fileBytes] must be the file range `window.fileStart .. window.fileEnd`.
  /// Returns an empty list when the bytes do not line up, which the caller
  /// treats as a failed feed (the engine simply asks again).
  Uint8List assemble(AacWindow window, Uint8List fileBytes) {
    final expected = window.fileEnd - window.fileStart;
    if (fileBytes.length < expected) return Uint8List(0);

    final out = BytesBuilder(copy: false);
    for (var i = window.firstSample; i <= window.lastSample; i++) {
      final localStart = _sampleOffsets[i] - window.fileStart;
      final size = _sampleSizes[i];
      if (localStart < 0 || localStart + size > fileBytes.length) return Uint8List(0);
      out.add(_adtsHeader(size, srIndex, channelConfig, profile));
      out.add(Uint8List.sublistView(fileBytes, localStart, localStart + size));
    }
    return out.takeBytes();
  }

  /// The 7-byte ADTS frame header for a payload of [payloadBytes].
  ///
  /// Public so the byte layout can be pinned by a test without a device.
  static Uint8List adtsHeader(
    int payloadBytes,
    int srIndex,
    int channelConfig, {
    int profile = 1,
  }) =>
      _adtsHeader(payloadBytes, srIndex, channelConfig, profile);

  static Uint8List _adtsHeader(
    int payloadBytes,
    int srIndex,
    int channelConfig,
    int profile,
  ) {
    final length = payloadBytes + adtsHeaderBytes;
    return Uint8List.fromList([
      0xFF,
      0xF1, // sync, MPEG-4, layer 0, no CRC
      ((profile & 0x03) << 6) |
          ((srIndex & 0x0F) << 2) |
          ((channelConfig >> 2) & 0x01),
      ((channelConfig & 0x03) << 6) | ((length >> 11) & 0x03),
      (length >> 3) & 0xFF,
      ((length & 0x07) << 5) | 0x1F, // + buffer fullness (VBR)
      0xFC, // buffer fullness low + one frame per block
    ]);
  }
}

/// A frame-aligned slice of the ADTS stream and the file bytes it needs.
class AacWindow {
  const AacWindow({
    required this.adtsOffset,
    required this.firstSample,
    required this.lastSample,
    required this.fileStart,
    required this.fileEnd,
    required this.adtsBytes,
  });

  /// Offset of the first frame in the assembled ADTS stream.
  final int adtsOffset;
  final int firstSample;
  final int lastSample;

  /// Inclusive byte range of the source file: read `[fileStart, fileEnd)`.
  final int fileStart;
  final int fileEnd;

  /// Size of the assembled ADTS chunk.
  final int adtsBytes;

  int get frameCount => lastSample - firstSample + 1;
}

// --------------------------------------------------------------------- boxes

class _Box {
  const _Box(this.type, this.end, this.payload, this.truncated);

  final String type;

  /// One past the last byte of this box inside the window.
  final int end;

  /// First byte after the box header.
  final int payload;

  /// The box runs past the end of the window (its table is incomplete).
  final bool truncated;
}

List<_Box> _boxes(Uint8List d, int from, int to) {
  final out = <_Box>[];
  var at = from;
  while (at + 8 <= to) {
    var size = _u32(d, at);
    final type = _ascii(d, at + 4, 4);
    var header = 8;
    if (size == 1) {
      if (at + 16 > to) break;
      size = _u64(d, at + 8);
      header = 16;
    } else if (size == 0) {
      size = to - at;
    }
    if (size < header) break;
    final end = at + size;
    final truncated = end > to;
    out.add(_Box(type, truncated ? to : end, at + header, truncated));
    if (truncated) break;
    at = end;
  }
  return out;
}

_Box? _first(List<_Box> boxes, String type) {
  for (final box in boxes) {
    if (box.type == type) return box;
  }
  return null;
}

/// Walks the MPEG-4 descriptor tree inside `esds` and returns the
/// AudioSpecificConfig (tag 0x05) — the two bytes the ADTS header is built
/// from. Descriptor lengths are base-128: every byte but the last has bit 7
/// set.
Uint8List? _readAsc(Uint8List d, int from, int to) {
  Uint8List? walk(int start, int limit, int depth) {
    var at = start;
    while (at < limit && depth < 8) {
      final tag = d[at++];
      var length = 0;
      var lengthBytes = 0;
      while (at < limit && lengthBytes < 4) {
        final b = d[at++];
        lengthBytes++;
        length = (length << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      final end = (at + length).clamp(0, limit);
      if (tag == 0x03) {
        // ES_Descriptor: ES_ID(2) + flags(1), then nested descriptors.
        final nested = walk(at + 3, end, depth + 1);
        if (nested != null) return nested;
      } else if (tag == 0x04) {
        // DecoderConfigDescriptor: objectType(1) streamType(1) bufferSize(3)
        // maxBitrate(4) avgBitrate(4), then nested descriptors.
        final nested = walk(at + 13, end, depth + 1);
        if (nested != null) return nested;
      } else if (tag == 0x05) {
        if (end - at < 2) return null;
        return Uint8List.sublistView(d, at, end);
      }
      if (end <= at && length == 0) break;
      at = end;
    }
    return null;
  }

  return walk(from, to, 0);
}

int _u16(Uint8List d, int at) => (d[at] << 8) | d[at + 1];

int _u32(Uint8List d, int at) =>
    (d[at] << 24) | (d[at + 1] << 16) | (d[at + 2] << 8) | d[at + 3];

int _u64(Uint8List d, int at) => (_u32(d, at) << 32) | _u32(d, at + 4);

String _ascii(Uint8List d, int at, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    final code = d[at + i];
    buffer.writeCharCode(code >= 32 && code < 127 ? code : 0x2E);
  }
  return buffer.toString();
}
