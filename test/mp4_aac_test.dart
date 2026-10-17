// Guards for the MP4 -> ADTS demuxer that makes instant playback possible.
//
// `flutter_soloud` decodes a whole MP4 before the first sample, so Musify reads
// the container's sample table itself and wraps each raw AAC frame in an ADTS
// header for the pull-buffer stream. A byte-level mistake here is not subtle —
// it is a buzz, a stall, or silence — and it cannot be caught on a workstation
// any other way, so the container is built by hand below and every offset is
// asserted against it.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/mp4_aac.dart';
import 'package:musify/services/media_cache.dart';

// ------------------------------------------------------------------ fixture
//
// A miniature but structurally exact faststart MP4: ftyp, moov (one `soun`
// track with an AAC-LC sample entry) and an mdat holding six "frames" that sit
// at absolute offsets 1000 / 1100 / 1200 / 1280 / 1400 / 1460.
//
// Chunks (stco) are 1000, 1200, 1400 and every chunk holds two samples (stsc),
// which is exactly the shape real JioSaavn files have — `stsc`/`stco` runs the
// sample table in batches, not one chunk per sample.

const _chunkOffsets = [1000, 1200, 1400];
const _sampleSizes = [100, 90, 80, 70, 60, 50];
const _fileLength = 1600;
const _sampleCount = 6;

/// The first bytes of every raw AAC frame, so `assemble` can be verified
/// byte-for-byte rather than by length.
Uint8List _sampleBytes(int index) =>
    Uint8List.fromList(List.generate(_sampleSizes[index], (i) => index + i));

Uint8List _sampleFile() {
  final file = Uint8List(_fileLength);
  var sample = 0;
  for (final chunk in _chunkOffsets) {
    var at = chunk;
    for (var inChunk = 0; inChunk < 2; inChunk++) {
      final bytes = _sampleBytes(sample);
      file.setRange(at, at + bytes.length, bytes);
      at += bytes.length;
      sample++;
    }
  }
  return file;
}

Uint8List _u16(int value) =>
    Uint8List.fromList([(value >> 8) & 0xFF, value & 0xFF]);

Uint8List _u32(int value) => Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

/// A box: 32-bit size, four-character type, then payload.
Uint8List _box(String type, List<int> payload) {
  final builder = BytesBuilder(copy: false)
    ..add(_u32(8 + payload.length))
    ..add(_ascii(type))
    ..add(payload);
  return builder.takeBytes();
}

/// `full box`: version/flags then payload. Every table in `stbl` is one.
Uint8List _full(String type, List<int> payload) =>
    _box(type, [0, 0, 0, 0, ...payload]);

Uint8List _stsd() {
  // AudioSampleEntry (version 0): reserved(6) dri(2) reserved[2](8)
  // channels(2) sampleSize(2) predefined(2) reserved(2) rate(4, 16.16),
  // then the esds descriptor tree carrying the AudioSpecificConfig.
  final entry = _box('mp4a', [
    ...List.filled(6, 0), 0, 1, // reserved, data_reference_index
    ...List.filled(8, 0), // reserved[2]
    ..._u16(2), // channels
    ..._u16(16), // sample size
    ..._u16(0), // pre_defined
    ..._u16(0), // reserved
    ..._u32(44100 << 16), // sample rate
    // esds -> DecoderConfigDescriptor -> DecoderSpecificInfo.
    // AAC-LC, 44100 Hz, stereo => ASC 0x12 0x10.
    ..._full('esds', [
      0x03, 0x19, 0x00, 0x01, 0x00, // ES_Descriptor
      0x04, 0x11, 0x40, 0x15, 0, 0, 0, 0, 0, 1, 0xF4, 0, 0, 1, 0xF4, // DCD
      0x05, 0x02, 0x12, 0x10, // DecoderSpecificInfo = AudioSpecificConfig
      0x06, 0x01, 0x02, // SLConfigDescriptor
    ]),
  ]);
  return _full('stsd', [0, 0, 0, 1, ...entry]);
}

Uint8List _stbl() {
  final stts = _full('stts', [
    ..._u32(1), // one run
    ..._u32(_sampleCount), // every sample...
    ..._u32(1024), // ...is 1024 AAC samples long
  ]);
  final stsc = _full('stsc', [
    ..._u32(1), // one run: chunks 1..N hold two samples each
    ..._u32(1),
    ..._u32(2),
    ..._u32(1),
  ]);
  final stsz = _full('stsz', [
    ..._u32(0), // variable sizes
    ..._u32(_sampleCount),
    for (final size in _sampleSizes) ..._u32(size),
  ]);
  final stco = _full('stco', [
    ..._u32(_chunkOffsets.length),
    for (final offset in _chunkOffsets) ..._u32(offset),
  ]);
  return _box('stbl', [
    ..._stsd(),
    ...stts,
    ...stsc,
    ...stsz,
    ...stco,
  ]);
}

Uint8List _moov() {
  final hdlr = _full('hdlr', [
    ..._u32(0), // pre_defined
    ..._ascii('soun'), // handler_type
    ...List.filled(12, 0), // reserved
    ..._ascii('Musify'), // name
  ]);
  final minf = _box('minf', _stbl());
  final mdia = _box('mdia', [...hdlr, ...minf]);
  final trak = _box('trak', mdia);
  return _box('moov', trak);
}

Uint8List _mp4Head() {
  final ftyp = _box('ftyp', [..._ascii('M4A '), ..._u32(0), ..._ascii('isom')]);
  return Uint8List.fromList([...ftyp, ..._moov()]);
}

/// What the six frames add up to: 6 headers + the sums of the sample sizes.
const _adtsTotal = 6 * 7 + 100 + 90 + 80 + 70 + 60 + 50;

void main() {
  group('Mp4AacIndex.parse', () {
    final index = Mp4AacIndex.parse(_mp4Head(), fileLength: _fileLength);

    test('finds the sound track and its codec configuration', () {
      expect(index, isNotNull, reason: 'a faststart M4A must be streamable');
      expect(index!.sampleCount, _sampleCount);
      expect(index.sampleRate, 44100);
      expect(index.channels, 2);
      expect(index.srIndex, 4, reason: '44100 Hz is sampling index 4');
      expect(index.channelConfig, 2, reason: 'stereo is profile 2');
      expect(index.samplesPerFrame, 1024);
    });

    test('derives the exact duration from the (sample, delta) table', () {
      // 6 frames x 1024 samples at 44100 Hz.
      expect(index!.duration.inMicroseconds, (6144 * 1000000 / 44100).round());
    });

    test('accounts for the 7-byte header on every frame', () {
      expect(index!.totalAdtsBytes, _adtsTotal);
      expect(index.totalFileBytes, 1510, reason: 'last sample ends at 1510');
    });

    test('places every sample at its chunk offset plus the sizes before it',
        () {
      // Explicit, readable assertions for the layout that matters: the parser
      // has to walk `stsc` runs *and* accumulate `stsz` sizes inside a chunk,
      // because real files put several frames in one chunk.
      final first = index!.windowAt(0, 16);
      expect(first.firstSample, 0);
      expect(first.lastSample, 0, reason: '16 bytes is less than one frame');
      expect(first.fileStart, 1000);
      expect(first.fileEnd, 1100);
      expect(first.adtsBytes, 107);

      // Frame 5 is the last of the file, in the third chunk.
      final last = index.windowAt(_adtsTotal - 1, 16);
      expect(last.firstSample, 5);
      expect(last.lastSample, 5);
      expect(last.fileStart, 1460, reason: 'chunk 3 + frame 0 (60 bytes)');
      expect(last.fileEnd, 1510);
      expect(last.adtsOffset, 435, reason: '5 headers + five sample sizes');
      expect(last.adtsBytes, 57);
    });

    test('a window spans whole frames and covers the asked-for bytes', () {
      final window = index!.windowAt(107, 100);
      expect(window.adtsOffset, 107, reason: 'aligned to a frame boundary');
      expect(window.firstSample, 1);
      expect(window.lastSample, 2, reason: 'frames 1+2 are 184 ADTS bytes');
      expect(window.fileStart, 1100);
      expect(window.fileEnd, 1280,
          reason: 'frames 1+2 are adjacent inside chunk 2');
      expect(window.adtsBytes, 184);
    });

    test('refuses anything it cannot prove', () {
      expect(Mp4AacIndex.parse(Uint8List(0), fileLength: 0), isNull);
      expect(Mp4AacIndex.parse(_moov().sublist(0, 40)), isNull,
          reason: 'a truncated moov has no usable table');

      // Fragmented MP4 has no sample table: the classic path must be used.
      final fragmented = Uint8List.fromList([
        ..._box('moof', List.filled(8, 0)),
        ..._moov(),
      ]);
      expect(Mp4AacIndex.parse(fragmented), isNull);

      // A sample count that does not match the chunk table is a reason to fall
      // back, not a reason to hand the engine nonsense.
      final head = _mp4Head();
      final stszCount = _indexOf(head, _ascii('stsz'));
      head[stszCount + 12] = 0xFF; // sample_count 6 -> absurd
      head[stszCount + 13] = 0xFF;
      expect(Mp4AacIndex.parse(head, fileLength: _fileLength), isNull);
    });

    test('rejects a table that points past the end of the file', () {
      expect(Mp4AacIndex.parse(_mp4Head(), fileLength: 1200), isNull,
          reason: 'samples live at 1460..1510');
    });
  });

  group('Mp4AacIndex.parseAnywhere', () {
    test('finds a moov that was written after the media', () {
      // A tail request: the window starts in the middle of mdat, so the box
      // walk cannot be trusted and the signature search has to do the work.
      final tail = Uint8List.fromList([
        ...List.filled(64, 0xAB),
        ..._moov(),
        ..._box('free', List.filled(16, 0)),
      ]);
      expect(Mp4AacIndex.parse(tail, fileLength: _fileLength), isNull,
          reason: 'a window that does not start on a box boundary');
      final index =
          Mp4AacIndex.parseAnywhere(tail, fileLength: _fileLength);
      expect(index, isNotNull);
      expect(index!.sampleCount, _sampleCount);
    });

    test('is a no-op for a normal faststart window', () {
      final index = Mp4AacIndex.parseAnywhere(_mp4Head(), fileLength: _fileLength);
      expect(index?.sampleCount, _sampleCount);
    });
  });

  group('ADTS assembly', () {
    test('the header is the canonical 44.1 kHz stereo AAC-LC header', () {
      expect(
        Mp4AacIndex.adtsHeader(100, 4, 2),
        [0xFF, 0xF1, 0x50, 0x80, 0x0D, 0x7F, 0xFC],
        reason: 'sync + MPEG-4 + no CRC, AAC-LC profile, 44.1k, stereo, '
            'frame length 107 = 0x6B spread over bits 30..42',
      );
    });

    test('a mono 22050 Hz frame carries its own profile and index', () {
      final header = Mp4AacIndex.adtsHeader(50, 7, 1);
      expect(header[0], 0xFF);
      expect(header[1], 0xF1);
      expect(header[2] >> 6, 1, reason: 'profile = AAC-LC (AOT 2) - 1');
      expect((header[2] >> 2) & 0x0F, 7, reason: '22050 Hz index');
      expect(((header[2] & 0x01) << 2) | (header[3] >> 6), 1,
          reason: 'mono channel configuration');
      final length = ((header[3] & 0x03) << 11) |
          (header[4] << 3) |
          (header[5] >> 5);
      expect(length, 57, reason: '7-byte header + 50-byte payload');
    });

    test('assembles frames byte-for-byte from the file bytes', () {
      final index = Mp4AacIndex.parse(_mp4Head(), fileLength: _fileLength)!;
      final file = _sampleFile();

      final window = index.windowAt(107, 100);
      final bytes = Uint8List.sublistView(file, window.fileStart, window.fileEnd);
      final adts = index.assemble(window, bytes);

      expect(adts.length, window.adtsBytes);
      // Frame 1 (index 1) comes first: header, then its payload.
      expect(adts.sublist(0, 7),
          Mp4AacIndex.adtsHeader(_sampleSizes[1], 4, 2));
      expect(adts.sublist(7, 7 + _sampleSizes[1]), _sampleBytes(1));
      // …then frame 2.
      final second = 7 + _sampleSizes[1];
      expect(adts.sublist(second, second + 7),
          Mp4AacIndex.adtsHeader(_sampleSizes[2], 4, 2));
      expect(
        adts.sublist(second + 7, second + 7 + _sampleSizes[2]),
        _sampleBytes(2),
      );
    });

    test('a short read is refused rather than assembled into noise', () {
      final index = Mp4AacIndex.parse(_mp4Head(), fileLength: _fileLength)!;
      final window = index.windowAt(0, 64 * 1024);
      expect(index.assemble(window, Uint8List(64)), isEmpty);
    });

    test('the whole stream can be walked from frame to frame', () {
      final index = Mp4AacIndex.parse(_mp4Head(), fileLength: _fileLength)!;
      final file = _sampleFile();
      final window = index.windowAt(0, 1 << 20); // everything
      final bytes =
          Uint8List.sublistView(file, window.fileStart, window.fileEnd);
      final adts = index.assemble(window, bytes);
      expect(adts.length, _adtsTotal);

      var at = 0;
      var frames = 0;
      while (at + 7 <= adts.length) {
        final length = ((adts[at + 3] & 0x03) << 11) |
            (adts[at + 4] << 3) |
            (adts[at + 5] >> 5);
        expect(length, _sampleSizes[frames] + 7,
            reason: 'frame $frames declares its own payload size');
        at += length;
        frames++;
      }
      expect(at, adts.length, reason: 'no slack, no overlap');
      expect(frames, _sampleCount);
    });
  });

  group('ByteCoverage', () {
    test('tracks holes, merges neighbours and knows when the file is whole',
        () {
      final coverage = ByteCoverage();
      coverage.add(0, 100);
      expect(coverage.bytes, 100);
      expect(coverage.covers(0, 100), isTrue);
      expect(coverage.covers(0, 101), isFalse);
      expect(coverage.firstGap(200), 100);
      expect(coverage.isComplete(200), isFalse);

      // A seek-forward leaves a hole behind it.
      coverage.add(150, 200);
      expect(coverage.bytes, 150);
      expect(coverage.firstGap(200), 100);
      expect(coverage.runAt(120), isNull);
      expect(coverage.runAt(160), (150, 200));

      // Filling the hole must merge everything into one run.
      coverage.add(100, 150);
      expect(coverage.ranges, [(0, 200)]);
      expect(coverage.firstGap(200), isNull);
      expect(coverage.isComplete(200), isTrue);
      expect(coverage.bytes, 200);
    });

    test('absorbs an overlapping range without double counting', () {
      final coverage = ByteCoverage()..add(0, 10)..add(20, 30);
      coverage.add(5, 25);
      expect(coverage.ranges, [(0, 30)]);
      expect(coverage.bytes, 30);
      coverage.add(30, 40);
      expect(coverage.ranges, [(0, 40)], reason: 'adjacent ranges merge too');
      expect(coverage.isComplete(40), isTrue);
    });

    test('an empty range changes nothing', () {
      final coverage = ByteCoverage()..add(10, 10);
      expect(coverage.ranges, isEmpty);
      expect(coverage.firstGap(10), 0);
      expect(coverage.isComplete(0), isFalse);
    });
  });
}

/// Finds a 4-byte box type in [data], or -1 — used to poke a fixture.
int _indexOf(Uint8List data, Uint8List needle) {
  outer:
  for (var at = 0; at + needle.length <= data.length; at++) {
    for (var i = 0; i < needle.length; i++) {
      if (data[at + i] != needle[i]) continue outer;
    }
    return at;
  }
  return -1;
}
