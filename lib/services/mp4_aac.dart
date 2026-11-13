import 'dart:math' as math;
import 'dart:typed_data';

import 'media_cache.dart' show StreamSession;

class SidxFragment {
  const SidxFragment({
    required this.fileOffset,
    required this.fileSize,
    required this.durationUs,
    required this.startUs,
  });
  final int fileOffset;
  final int fileSize;
  final int durationUs;
  final int startUs;

  Duration get startTime => Duration(microseconds: startUs);
  Duration get duration => Duration(microseconds: durationUs);
}

/// The AAC audio inside a progressive or fragmented MP4 file, indexed for
/// byte-range reading.
///
/// ## Why this exists
/// `flutter_soloud` cannot stream MP4/M4A: the platform decoder for those
/// containers is `MediaExtractor` + `MediaCodec`, which decodes the **entire**
/// file to PCM at load time. A 10 MB, 4½-minute JioSaavn or YouTube track
/// therefore costs its download *plus* a full AAC decode before the first
/// sample is audible.
///
/// The engine *can* stream plain AAC, though: `setPullBufferStream` with
/// `BufferType.auto` feeds an ADTS elementary stream to a decoder that runs on
/// demand. So Musify reads the MP4's sample tables (`moov` for faststart, or
/// sequential `moof` fragments for YouTube), wraps each raw AAC frame in a
/// 7-byte ADTS header, and hands the engine frames as they are needed.
/// Playback then starts after ~96–128 KB instead of ~10 MB, and there is no
/// full-file PCM decode at all.
class Mp4AacIndex {
  Mp4AacIndex._({
    required List<int> sampleOffsets,
    required List<int> sampleSizes,
    required List<int> adtsStarts,
    required this.sampleRate,
    required this.channels,
    required this.srIndex,
    required this.channelConfig,
    required this.samplesPerFrame,
    required Duration duration,
    this.isFragmented = false,
    int lastParsedBoxEnd = 0,
    int? estimatedTotalBytes,
    Duration? fallbackDuration,
    this.sidxFragments,
  })  : _sampleOffsets = sampleOffsets,
        _sampleSizes = sampleSizes,
        _adtsStarts = adtsStarts,
        _duration = duration,
        _lastParsedBoxEnd = lastParsedBoxEnd,
        _estimatedTotalBytes = estimatedTotalBytes,
        _fallbackDuration = fallbackDuration;

  final List<SidxFragment>? sidxFragments;
  Duration _baseTime = Duration.zero;

  Duration get baseTime => _baseTime;

  /// Bytes added in front of every raw AAC frame.
  static const int adtsHeaderBytes = 7;

  /// ADTS carries AAC-LC as profile 1; anything else is rejected rather than
  /// mis-declared.
  static const int profile = 1;

  /// Sample entry types that mean "AAC in this stsd".
  static const Set<String> _audioEntryTypes = {'mp4a', 'aac '};

  final List<int> _sampleOffsets;
  final List<int> _sampleSizes;

  /// `_adtsStarts[i]` is the byte offset of frame `i` inside the ADTS stream;
  /// `_adtsStarts[sampleCount]` is therefore the stream's total length.
  final List<int> _adtsStarts;

  final int sampleRate;
  final int channels;
  final int srIndex;
  final int channelConfig;
  final int samplesPerFrame;
  final Duration _duration;
  final bool isFragmented;
  final int? _estimatedTotalBytes;
  final Duration? _fallbackDuration;

  int _lastParsedBoxEnd;
  bool _isFullyParsed = false;

  int get sampleCount => _sampleSizes.length;

  int get parsedAdtsBytes =>
      _adtsStarts.isEmpty ? 0 : _adtsStarts[sampleCount];

  /// Total size of the assembled ADTS elementary stream.
  int get totalAdtsBytes {
    if (!isFragmented || _isFullyParsed) {
      return parsedAdtsBytes;
    }
    final current = parsedAdtsBytes;
    return math.max(current, _estimatedTotalBytes ?? current);
  }

  Duration get duration {
    if (sidxFragments != null && sidxFragments!.isNotEmpty) {
      final last = sidxFragments!.last;
      return Duration(microseconds: last.startUs + last.durationUs);
    }
    if (!isFragmented || _isFullyParsed) {
      return _duration;
    }
    return _fallbackDuration ?? _duration;
  }

  int get totalFileBytes => _sampleOffsets.isEmpty
      ? 0
      : _sampleOffsets[sampleCount - 1] + _sampleSizes[sampleCount - 1];

  /// Parses a byte window that contains a complete `moov` box.
  ///
  /// Supports both standard faststart MP4 (with a complete sample table in
  /// `moov`) and fragmented MP4 (`fMP4`), where initial fragments in [window]
  /// are parsed immediately and subsequent fragments can be loaded via
  /// [ensureCovered].
  static Mp4AacIndex? parse(
    Uint8List window, {
    int? fileLength,
    Duration? fallbackDuration,
  }) {
    if (window.length < 40) return null;
    try {
      final top = _boxes(window, 0, window.length);
      if (top.isEmpty) return null;

      final moov = _first(top, 'moov');
      if (moov == null || moov.truncated) return null;

      _Box? soundTrak;
      _CodecConfig? codec;
      for (final trak in _boxes(window, moov.payload, moov.end)) {
        if (trak.type != 'trak') continue;
        final c = _codecConfigFromTrak(window, trak);
        if (c != null) {
          soundTrak = trak;
          codec = c;
          break;
        }
      }
      if (soundTrak == null || codec == null) return null;

      // 1. Try standard progressive MP4 first if there is no moof box.
      if (!top.any((b) => b.type == 'moof')) {
        final standard =
            _standardFromTrak(window, soundTrak, codec, fileLength);
        if (standard != null && standard.sampleCount > 0) return standard;
      }

      // 2. Fragmented MP4: moof fragments carry the audio runs.
      List<SidxFragment>? sidxFragments;
      for (final box in top) {
        if (box.type == 'sidx' && !box.truncated) {
          sidxFragments = _parseSidx(window, box);
        }
      }

      final sampleOffsets = <int>[];
      final sampleSizes = <int>[];
      final adtsStarts = <int>[0];
      var lastParsedBoxEnd = moov.end;

      for (final box in top) {
        if (box.start < moov.end) continue;
        if (box.type == 'moof') {
          if (box.truncated) break;
          _parseMoof(
            window,
            box,
            moofFileOffset: box.start,
            sampleOffsets: sampleOffsets,
            sampleSizes: sampleSizes,
            adtsStarts: adtsStarts,
          );
          lastParsedBoxEnd = box.end;
        } else if (box.type == 'mdat') {
          if (box.truncated) {
            lastParsedBoxEnd = box.start;
            break;
          }
          lastParsedBoxEnd = box.end;
        } else {
          if (box.truncated) break;
          lastParsedBoxEnd = box.end;
        }
      }

      if (sampleOffsets.isEmpty) return null;

      final estimatedAdts = fileLength != null && fileLength > 0
          ? (fileLength * 1.015).round()
          : (fallbackDuration != null && fallbackDuration > Duration.zero
              ? ((fallbackDuration.inMicroseconds * codec.sampleRate) /
                      (1000000 * codec.samplesPerFrame) *
                      (codec.samplesPerFrame * 0.36 + adtsHeaderBytes))
                  .round()
              : adtsStarts.last);

      final initialMicros =
          ((sampleOffsets.length * codec.samplesPerFrame * 1000000) /
                  codec.sampleRate)
              .round();

      return Mp4AacIndex._(
        sampleOffsets: sampleOffsets,
        sampleSizes: sampleSizes,
        adtsStarts: adtsStarts,
        sampleRate: codec.sampleRate,
        channels: codec.channels,
        srIndex: codec.srIndex,
        channelConfig: codec.channelConfig,
        samplesPerFrame: codec.samplesPerFrame,
        duration: fallbackDuration ?? Duration(microseconds: initialMicros),
        isFragmented: true,
        lastParsedBoxEnd: lastParsedBoxEnd,
        estimatedTotalBytes: estimatedAdts,
        fallbackDuration: fallbackDuration,
        sidxFragments: sidxFragments,
      );
    } catch (_) {
      return null;
    }
  }

  /// Incrementally parses subsequent moof/mdat boxes from [session] up to
  /// [targetAdtsOffset] (or until EOF when [session] is complete).
  Future<void> ensureCovered(
    int targetAdtsOffset,
    StreamSession session,
  ) async {
    if (!isFragmented || _isFullyParsed) return;
    if (_adtsStarts.length > 1 &&
        _adtsStarts.last >= targetAdtsOffset &&
        !session.isComplete) {
      return;
    }

    final total = session.total;
    while (!_isFullyParsed) {
      if (_adtsStarts.length > 1 &&
          _adtsStarts.last >= targetAdtsOffset &&
          !session.isComplete) {
        break;
      }
      if (total != null && _lastParsedBoxEnd >= total) {
        _isFullyParsed = true;
        break;
      }

      final headerEnd =
          math.min(_lastParsedBoxEnd + 16, total ?? (_lastParsedBoxEnd + 16));
      final header = await session.read(_lastParsedBoxEnd, headerEnd);
      if (header == null || header.length < 8) break;

      var boxSize = _u32(header, 0);
      final boxType = _ascii(header, 4, 4);
      var headerBytes = 8;
      if (boxSize == 1) {
        if (header.length < 16) break;
        boxSize = _u64(header, 8);
        headerBytes = 16;
      } else if (boxSize == 0) {
        if (total != null) {
          boxSize = total - _lastParsedBoxEnd;
        } else {
          break;
        }
      }
      if (boxSize < headerBytes) break;

      final boxEnd = _lastParsedBoxEnd + boxSize;
      if (total != null && boxEnd > total) {
        _isFullyParsed = true;
        break;
      }

      if (boxType == 'moof') {
        final moofBytes = await session.read(_lastParsedBoxEnd, boxEnd);
        if (moofBytes == null || moofBytes.length < boxSize) break;
        final box = _Box(boxType, 0, boxSize, headerBytes, false);
        _parseMoof(
          moofBytes,
          box,
          moofFileOffset: _lastParsedBoxEnd,
          sampleOffsets: _sampleOffsets,
          sampleSizes: _sampleSizes,
          adtsStarts: _adtsStarts,
        );
        _lastParsedBoxEnd = boxEnd;
      } else {
        _lastParsedBoxEnd = boxEnd;
      }
    }
  }

  /// Parses enough fragments so that [time] is covered in the ADTS table.
  /// When an `sidx` box is present (YouTube DASH fMP4), jumps directly to the
  /// target fragment in a single HTTP request instead of walking intermediate
  /// boxes.
  Future<void> ensureCoveredTime(Duration time, StreamSession session) async {
    if (!isFragmented || _isFullyParsed) return;
    if (sidxFragments != null && sidxFragments!.isNotEmpty) {
      final targetUs = time.inMicroseconds;
      final frag = sidxFragments!.firstWhere(
        (f) => targetUs >= f.startUs && targetUs < (f.startUs + f.durationUs),
        orElse: () => sidxFragments!.last,
      );

      if (_baseTime == frag.startTime && _sampleOffsets.isNotEmpty) {
        return;
      }

      session.jumpTo(
        frag.fileOffset,
        frag.fileOffset + math.min(64 * 1024, frag.fileSize),
      );
      final readEnd = math.min(
        frag.fileOffset + 32 * 1024,
        session.total ?? (frag.fileOffset + 32 * 1024),
      );
      final header = await session.read(frag.fileOffset, readEnd);
      if (header != null && header.length >= 8) {
        final boxes = _boxes(header, 0, header.length);
        final moof = _first(boxes, 'moof');
        if (moof != null && !moof.truncated) {
          _sampleOffsets.clear();
          _sampleSizes.clear();
          _adtsStarts.clear();
          _adtsStarts.add(0);
          _baseTime = frag.startTime;

          _parseMoof(
            header,
            moof,
            moofFileOffset: frag.fileOffset,
            sampleOffsets: _sampleOffsets,
            sampleSizes: _sampleSizes,
            adtsStarts: _adtsStarts,
          );
          _lastParsedBoxEnd = frag.fileOffset + frag.fileSize;
          return;
        }
      }
    }

    final dur = duration;
    if (dur <= Duration.zero) return;
    final fraction = (time.inMicroseconds / dur.inMicroseconds).clamp(0.0, 1.0);
    final targetOffset = (totalAdtsBytes * fraction).round();
    await ensureCovered(targetOffset, session);
  }

  static List<SidxFragment>? _parseSidx(Uint8List d, _Box sidx) {
    if (sidx.end - sidx.payload < 24) return null;
    final version = d[sidx.payload];
    var at = sidx.payload + 4; // skip version (1) and flags (3)
    at += 4; // skip reference_id (4)
    final timescale = _u32(d, at);
    at += 4;
    if (timescale <= 0) return null;

    final int earliestTime;
    final int firstOffset;
    if (version == 0) {
      if (at + 8 > sidx.end) return null;
      earliestTime = _u32(d, at);
      firstOffset = _u32(d, at + 4);
      at += 8;
    } else {
      if (at + 16 > sidx.end) return null;
      earliestTime = _u64(d, at);
      firstOffset = _u64(d, at + 8);
      at += 16;
    }
    at += 2; // skip reserved (2)
    if (at + 2 > sidx.end) return null;
    final refCount = (d[at] << 8) | d[at + 1];
    at += 2;

    var curOffset = sidx.end + firstOffset;
    var curTimeUs = (earliestTime * 1000000) ~/ timescale;
    final fragments = <SidxFragment>[];

    for (var i = 0; i < refCount; i++) {
      if (at + 12 > sidx.end) break;
      final refInfo = _u32(d, at);
      final size = refInfo & 0x7FFFFFFF;
      final durUnits = _u32(d, at + 4);
      at += 12;
      final durUs = (durUnits * 1000000) ~/ timescale;
      fragments.add(
        SidxFragment(
          fileOffset: curOffset,
          fileSize: size,
          durationUs: durUs,
          startUs: curTimeUs,
        ),
      );
      curOffset += size;
      curTimeUs += durUs;
    }
    return fragments.isNotEmpty ? fragments : null;
  }

  /// Parses `moof` boxes and appends their sample runs.
  static void _parseMoof(
    Uint8List d,
    _Box moof, {
    required int moofFileOffset,
    required List<int> sampleOffsets,
    required List<int> sampleSizes,
    required List<int> adtsStarts,
  }) {
    final trafBoxes =
        _boxes(d, moof.payload, moof.end).where((b) => b.type == 'traf');
    for (final traf in trafBoxes) {
      final inner = _boxes(d, traf.payload, traf.end);
      final tfhd = _first(inner, 'tfhd');
      if (tfhd == null || tfhd.end - tfhd.payload < 8) continue;

      final tfFlags = (d[tfhd.payload + 1] << 16) |
          (d[tfhd.payload + 2] << 8) |
          d[tfhd.payload + 3];
      var at = tfhd.payload + 8; // skip version/flags (4) and track_id (4)

      int? baseDataOffset;
      if (tfFlags & 0x000001 != 0) {
        if (at + 8 > tfhd.end) continue;
        baseDataOffset = _u64(d, at);
        at += 8;
      }
      if (tfFlags & 0x000002 != 0) at += 4;
      if (tfFlags & 0x000008 != 0) at += 4;
      var defaultSampleSize = 0;
      if (tfFlags & 0x000010 != 0) {
        if (at + 4 > tfhd.end) continue;
        defaultSampleSize = _u32(d, at);
        at += 4;
      }
      if (tfFlags & 0x000020 != 0) at += 4;

      final baseOffset = baseDataOffset ?? moofFileOffset;

      final trunBoxes = inner.where((b) => b.type == 'trun');
      for (final trun in trunBoxes) {
        if (trun.end - trun.payload < 8) continue;
        final trFlags = (d[trun.payload + 1] << 16) |
            (d[trun.payload + 2] << 8) |
            d[trun.payload + 3];
        final runSampleCount = _u32(d, trun.payload + 4);
        var trAt = trun.payload + 8;
        var dataOffset = 0;
        if (trFlags & 0x000001 != 0) {
          if (trAt + 4 > trun.end) continue;
          dataOffset = _i32(d, trAt);
          trAt += 4;
        }
        if (trFlags & 0x000004 != 0) trAt += 4;

        var sampleFileOffset = baseOffset + dataOffset;
        for (var s = 0; s < runSampleCount; s++) {
          var size = defaultSampleSize;
          if (trFlags & 0x000100 != 0) {
            if (trAt + 4 > trun.end) break;
            trAt += 4;
          }
          if (trFlags & 0x000200 != 0) {
            if (trAt + 4 > trun.end) break;
            size = _u32(d, trAt);
            trAt += 4;
          }
          if (trFlags & 0x000400 != 0) {
            if (trAt + 4 > trun.end) break;
            trAt += 4;
          }
          if (trFlags & 0x000800 != 0) {
            if (trAt + 4 > trun.end) break;
            trAt += 4;
          }
          if (size <= 0) continue;
          sampleOffsets.add(sampleFileOffset);
          sampleSizes.add(size);
          adtsStarts.add(adtsStarts.last + adtsHeaderBytes + size);
          sampleFileOffset += size;
        }
      }
    }
  }

  /// The end offset of a top-level `moov` that starts inside [window].
  static int? moovEndIn(Uint8List window) {
    var at = 0;
    while (at + 8 <= window.length) {
      var size = _u32(window, at);
      final type = _ascii(window, at + 4, 4);
      var header = 8;
      if (size == 1) {
        if (at + 16 > window.length) return null;
        size = _u64(window, at + 8);
        header = 16;
      } else if (size == 0) {
        return null; // "until end of file"
      }
      if (size < header) return null;
      if (type == 'moov') return at + size;
      if (at + size > window.length) return null;
      at += size;
    }
    return null;
  }

  /// The end offset of a top-level `sidx` that starts inside [window].
  static int? sidxEndIn(Uint8List window) {
    var at = 0;
    while (at + 8 <= window.length) {
      var size = _u32(window, at);
      final type = _ascii(window, at + 4, 4);
      var header = 8;
      if (size == 1) {
        if (at + 16 > window.length) return null;
        size = _u64(window, at + 8);
        header = 16;
      } else if (size == 0) {
        return null; // "until end of file"
      }
      if (size < header) return null;
      if (type == 'sidx') return at + size;
      if (at + size > window.length) return null;
      at += size;
    }
    return null;
  }

  /// Parses a window that may start in the middle of a file.
  static Mp4AacIndex? parseAnywhere(
    Uint8List window, {
    int? fileLength,
    Duration? fallbackDuration,
  }) {
    final direct = parse(
      window,
      fileLength: fileLength,
      fallbackDuration: fallbackDuration,
    );
    if (direct != null) return direct;
    if (window.length < 16) return null;

    for (var at = 0; at + 8 <= window.length; at++) {
      if (window[at + 4] != 0x6D ||
          window[at + 5] != 0x6F ||
          window[at + 6] != 0x6F ||
          window[at + 7] != 0x76) {
        continue;
      }
      final candidate = parse(
        Uint8List.sublistView(window, at),
        fileLength: fileLength,
        fallbackDuration: fallbackDuration,
      );
      if (candidate != null) return candidate;
    }
    return null;
  }

  /// The frame that contains ADTS byte [adtsOffset] (clamped into range).
  int sampleAt(int adtsOffset) {
    if (adtsOffset <= 0) return 0;
    if (sampleCount <= 0) return 0;
    if (adtsOffset >= _adtsStarts.last) return sampleCount - 1;
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

  /// The frame index for a given playback [time].
  int sampleAtTime(Duration time) {
    if (sampleCount <= 0) return 0;
    final relTime = time > _baseTime ? time - _baseTime : Duration.zero;
    final dur = duration - _baseTime;
    if (dur > Duration.zero && relTime >= dur) return sampleCount - 1;
    final seconds = relTime.inMicroseconds / 1000000.0;
    final frame = ((seconds * sampleRate) / samplesPerFrame).floor();
    return frame.clamp(0, sampleCount - 1);
  }

  /// The byte offset in the ADTS stream where the frame for [time] begins.
  int adtsOffsetAtTime(Duration time) {
    final frame = sampleAtTime(time);
    return _adtsStarts[frame];
  }

  /// The exact timestamp of the frame that contains ADTS byte [adtsOffset].
  Duration timeAtAdtsOffset(int adtsOffset) {
    if (sampleCount <= 0) return _baseTime;
    final frame = sampleAt(adtsOffset);
    final micros = ((frame * samplesPerFrame * 1000000) / sampleRate).round();
    return _baseTime + Duration(microseconds: micros);
  }

  /// A read window covering at least [maxBytes] of ADTS stream from
  /// [adtsOffset], aligned to frame boundaries.
  AacWindow windowAt(int adtsOffset, int maxBytes) {
    final first = sampleAt(adtsOffset);
    final from = _adtsStarts[first];
    final target =
        from + (maxBytes < adtsHeaderBytes ? adtsHeaderBytes : maxBytes);
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
  Uint8List assemble(AacWindow window, Uint8List fileBytes) {
    final expected = window.fileEnd - window.fileStart;
    if (fileBytes.length < expected) return Uint8List(0);

    final out = BytesBuilder(copy: false);
    for (var i = window.firstSample; i <= window.lastSample; i++) {
      final localStart = _sampleOffsets[i] - window.fileStart;
      final size = _sampleSizes[i];
      if (localStart < 0 || localStart + size > fileBytes.length) {
        return Uint8List(0);
      }
      out.add(_adtsHeader(size, srIndex, channelConfig, profile));
      out.add(Uint8List.sublistView(fileBytes, localStart, localStart + size));
    }
    return out.takeBytes();
  }

  /// The 7-byte ADTS frame header for a payload of [payloadBytes].
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

class _CodecConfig {
  const _CodecConfig({
    required this.channels,
    required this.sampleRate,
    required this.srIndex,
    required this.channelConfig,
    required this.samplesPerFrame,
  });

  final int channels;
  final int sampleRate;
  final int srIndex;
  final int channelConfig;
  final int samplesPerFrame;
}

_CodecConfig? _codecConfigFromTrak(Uint8List d, _Box trak) {
  final mdia = _first(_boxes(d, trak.payload, trak.end), 'mdia');
  if (mdia == null) return null;

  final mdiaBoxes = _boxes(d, mdia.payload, mdia.end);
  final hdlr = _first(mdiaBoxes, 'hdlr');
  if (hdlr != null && hdlr.end - hdlr.payload >= 12) {
    if (_ascii(d, hdlr.payload + 8, 4) != 'soun') return null;
  }

  final minf = _first(mdiaBoxes, 'minf');
  if (minf == null) return null;
  final stbl = _first(_boxes(d, minf.payload, minf.end), 'stbl');
  if (stbl == null) return null;
  final stblBoxes = _boxes(d, stbl.payload, stbl.end);

  final stsd = _first(stblBoxes, 'stsd');
  if (stsd == null || stsd.end - stsd.payload < 16) return null;
  final entries = _boxes(d, stsd.payload + 8, stsd.end);
  if (entries.isEmpty) return null;
  final entry = entries.first;
  if (!Mp4AacIndex._audioEntryTypes.contains(entry.type)) return null;
  if (entry.end - entry.payload < 28) return null;

  final channels = _u16(d, entry.payload + 16);
  final sampleRate = _u32(d, entry.payload + 24) >> 16;
  if (channels < 1 ||
      channels > 8 ||
      sampleRate < 8000 ||
      sampleRate > 192000) {
    return null;
  }

  final esds = _first(_boxes(d, entry.payload + 28, entry.end), 'esds');
  if (esds == null) return null;
  final asc = _readAsc(d, esds.payload + 4, esds.end);
  if (asc == null || asc.length < 2) return null;

  final aot = asc[0] >> 3;
  if (aot != 2) return null; // AAC-LC only.
  final srIndex = ((asc[0] & 0x07) << 1) | (asc[1] >> 7);
  final channelConfig = (asc[1] >> 3) & 0x0F;
  if (srIndex > 12 || channelConfig == 0 || channelConfig > 7) return null;

  var samplesPerFrame = 1024;
  final stts = _first(stblBoxes, 'stts');
  if (stts != null && stts.end - stts.payload >= 12) {
    final firstDelta = _u32(d, stts.payload + 12);
    if (firstDelta > 0 && firstDelta <= 8192) samplesPerFrame = firstDelta;
  }

  return _CodecConfig(
    channels: channels,
    sampleRate: sampleRate,
    srIndex: srIndex,
    channelConfig: channelConfig,
    samplesPerFrame: samplesPerFrame,
  );
}

Mp4AacIndex? _standardFromTrak(
  Uint8List d,
  _Box trak,
  _CodecConfig codec,
  int? fileLength,
) {
  final mdia = _first(_boxes(d, trak.payload, trak.end), 'mdia');
  if (mdia == null) return null;
  final minf = _first(_boxes(d, mdia.payload, mdia.end), 'minf');
  if (minf == null) return null;
  final stbl = _first(_boxes(d, minf.payload, minf.end), 'stbl');
  if (stbl == null) return null;
  final stblBoxes = _boxes(d, stbl.payload, stbl.end);

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
    final nextFirstChunk = (run + 1 < runCount && nextAt + 12 <= stsc.end)
        ? _u32(d, nextAt)
        : chunkCount + 1;
    if (perChunk == 0 || firstChunk == 0) return null;

    for (var chunk = firstChunk;
        chunk < nextFirstChunk && chunk <= chunkCount && placed < sampleCount;
        chunk++) {
      var offset = chunkOffset(chunk - 1);
      for (var inChunk = 0;
          inChunk < perChunk && placed < sampleCount;
          inChunk++) {
        offsets[placed] = offset;
        offset += sizes[placed];
        placed++;
      }
    }
  }
  if (placed != sampleCount) return null;

  var ticks = 0;
  final sttsEntries = _u32(d, stts.payload + 4);
  for (var i = 0; i < sttsEntries; i++) {
    final at = stts.payload + 8 + i * 8;
    if (at + 8 > stts.end) break;
    final count = _u32(d, at);
    final delta = _u32(d, at + 4);
    ticks += count * delta;
  }
  final micros = ticks > 0
      ? (ticks * 1000000 / codec.sampleRate).round()
      : (sampleCount * codec.samplesPerFrame * 1000000 / codec.sampleRate)
          .round();

  final starts = Uint32List(sampleCount + 1);
  var cursor = 0;
  for (var i = 0; i < sampleCount; i++) {
    starts[i] = cursor;
    cursor += Mp4AacIndex.adtsHeaderBytes + sizes[i];
  }
  starts[sampleCount] = cursor;

  if (fileLength != null) {
    final last = offsets[sampleCount - 1] + sizes[sampleCount - 1];
    if (last > fileLength) return null;
  }

  return Mp4AacIndex._(
    sampleOffsets: offsets,
    sampleSizes: sizes,
    adtsStarts: starts,
    sampleRate: codec.sampleRate,
    channels: codec.channels,
    srIndex: codec.srIndex,
    channelConfig: codec.channelConfig,
    samplesPerFrame: codec.samplesPerFrame,
    duration: Duration(microseconds: micros),
    isFragmented: false,
    lastParsedBoxEnd: trak.end,
  );
}

class _Box {
  const _Box(this.type, this.start, this.end, this.payload, this.truncated);

  final String type;

  /// Absolute start offset inside the window or buffer.
  final int start;

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
    out.add(_Box(type, at, truncated ? to : end, at + header, truncated));
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
        final nested = walk(at + 3, end, depth + 1);
        if (nested != null) return nested;
      } else if (tag == 0x04) {
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

int _i32(Uint8List d, int at) {
  final v = _u32(d, at);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int _u64(Uint8List d, int at) => (_u32(d, at) << 32) | _u32(d, at + 4);

String _ascii(Uint8List d, int at, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    final code = d[at + i];
    buffer.writeCharCode(code >= 32 && code < 127 ? code : 0x2E);
  }
  return buffer.toString();
}
