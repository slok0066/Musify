// Scratch probe: what does a JioSaavn 320 kbps file actually look like on the
// wire? Needs to answer, for the "instant playback" work:
//   * which renditions exist (mp4 only, or mp3/aac too?),
//   * does the CDN honour Range requests,
//   * where is `moov` (front = faststart, or back?),
//   * are the samples plain AAC-LC in a single `mdat`, or fragmented `moof`?
// Run: dart run tool/mp4_probe.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _api = 'https://www.jiosaavn.com/api.php';

Future<void> main(List<String> args) async {
  final query = args.isNotEmpty ? args.join(' ') : 'kesariya';
  final client = HttpClient();

  final song = await _search(client, query);
  if (song == null) {
    print('search returned nothing');
    return;
  }
  print('SONG   : ${song['title']} — ${song['artist']}');
  print('ID     : ${song['id']}');

  final encrypted = song['encrypted_media_url'];
  if (encrypted == null || encrypted.isEmpty) {
    print('no encrypted_media_url');
    return;
  }
  final raw96 = _decrypt(encrypted);
  final url320 = raw96.replaceAll(RegExp(r'_\d+\.'), '_320.');
  print('decrypted: $raw96');
  print('320      : $url320');

  // Variant hunt: does the CDN serve anything other than MP4/AAC?
  final variants = <String, String>{
    '320 mp4': url320,
    '160 mp4': url320.replaceAll('_320.', '_160.'),
    '96 mp4': url320.replaceAll('_320.', '_96.'),
    '320 mp3': url320.replaceAll('_320.mp4', '_320.mp3'),
    '160 mp3': url320.replaceAll('_320.mp4', '_160.mp3'),
    '96 mp3': url320.replaceAll('_320.mp4', '_96.mp3'),
  };
  for (final entry in variants.entries) {
    await _sniff(client, entry.key, entry.value);
  }

  print('');
  print('=== structure of the 320 file ===');
  final total = await _length(client, url320);
  print('content-length: $total');

  final head = await _get(client, url320, 0, 65535);
  print('head bytes    : ${head.length}');
  _scanBoxes('head', head, 0);

  if (total != null && total > 0) {
    final tailStart = total - 524288 > 0 ? total - 524288 : 0;
    final tail = await _get(client, url320, tailStart, total - 1);
    print('tail bytes    : ${tail.length} (from $tailStart)');
    _scanBoxes('tail', tail, tailStart);

    final moovAt = _findBox(tail, tailStart, 'moov');
    if (moovAt != null) {
      print('moov found in tail at $moovAt');
      final moov = tail.sublist(moovAt.$2, (moovAt.$2 + moovAt.$3).clamp(0, tail.length));
      _dumpMoov(moov, moovAt.$1);
    } else {
      final moovHead = _findBox(head, 0, 'moov');
      if (moovHead != null) {
        print('moov found in head at ${moovHead.$1}');
        _dumpMoov(
          head.sublist(moovHead.$2, (moovHead.$2 + moovHead.$3).clamp(0, head.length)),
          moovHead.$1,
        );
      } else {
        print('moov NOT in head or tail');
      }
    }
  }
  client.close(force: true);
}

// ------------------------------------------------------------------ catalogue

Future<Map<String, dynamic>?> _search(HttpClient client, String query) async {
  final uri = Uri.parse('$_api?__call=search.getResults&q=${Uri.encodeQueryComponent(query)}'
      '&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=5&p=1');
  final request = await client.getUrl(uri);
  request.headers.set('User-Agent', 'Mozilla/5.0');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (!body.trim().startsWith('{')) return null;
  final json = jsonDecode(body) as Map<String, dynamic>;
  final results = (json['results'] as List?) ?? const [];
  for (final raw in results) {
    if (raw is! Map) continue;
    final map = raw.cast<String, dynamic>();
    final more = (map['more_info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final encrypted = more['encrypted_media_url']?.toString() ?? '';
    if (encrypted.isEmpty) continue;
    return {
      'id': map['id']?.toString() ?? '',
      'title': (map['title']?.toString() ?? '').replaceAll(RegExp(r'&quot;'), '"'),
      'artist': more['artistMap'] is Map ? 'various' : (map['subtitle']?.toString() ?? ''),
      'encrypted_media_url': encrypted,
    };
  }
  return null;
}

String _decrypt(String input) {
  var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(DESedeEngine()));
  final key = utf8.encode('38346591');
  cipher.init(
    false,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      // 3DES with three identical subkeys is single DES.
      KeyParameter(Uint8List.fromList([...key, ...key, ...key])),
      null,
    ),
  );
  final out = cipher.process(Uint8List.fromList(base64.decode(normalized)));
  return utf8.decode(out, allowMalformed: true);
}

// ------------------------------------------------------------------- transport

Future<int?> _length(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('Range', 'bytes=0-0');
  final response = await request.close();
  final range = response.headers.value('content-range');
  await response.drain<void>();
  if (range == null) return null;
  final slash = range.lastIndexOf('/');
  if (slash < 0) return null;
  return int.tryParse(range.substring(slash + 1).trim());
}

Future<Uint8List> _get(HttpClient client, String url, int start, int end) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('Range', 'bytes=$start-$end');
  final response = await request.close();
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> _sniff(HttpClient client, String label, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Range', 'bytes=0-15');
    final response = await request.close();
    final head = await response.fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) {
      b.add(c);
      return b;
    });
    final bytesCombined = head.takeBytes();
    final magic = bytesCombined.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii =
        bytesCombined.take(4).map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.').join();
    print('$label | ${response.statusCode} | len=${response.headers.value('content-length')} '
        '| type=${response.headers.value('content-type')} | $magic | $ascii');
  } catch (e) {
    print('$label | ERR $e');
  }
}

// ----------------------------------------------------------------- box parser

/// Top-level box walk over [data], whose first byte is at [base] in the file.
void _scanBoxes(String label, Uint8List data, int base) {
  var offset = 0;
  final found = <String, (int, int, int)>{}; // type -> (fileOffset, size, headerLen)
  while (offset + 8 <= data.length) {
    final size = _u32(data, offset);
    final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    var header = 8;
    var boxSize = size;
    if (size == 1 && offset + 16 <= data.length) {
      boxSize = _u64(data, offset + 8);
      header = 16;
    } else if (size == 0) {
      boxSize = data.length - offset;
    }
    if (boxSize < header) break;
    found[type] = (base + offset, boxSize, header);
    print('  [$label] $type at ${base + offset} size=$boxSize header=$header');
    if (boxSize > data.length - offset) break; // runs past this window
    offset += boxSize;
  }
}

(int, int, int)? _findBox(Uint8List data, int base, String type) {
  var offset = 0;
  while (offset + 8 <= data.length) {
    final size = _u32(data, offset);
    final kind = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    var header = 8;
    var boxSize = size;
    if (size == 1 && offset + 16 <= data.length) {
      boxSize = _u64(data, offset + 8);
      header = 16;
    } else if (size == 0) {
      boxSize = data.length - offset;
    }
    if (boxSize < header) return null;
    if (kind == type) return (base + offset, offset + header, boxSize - header);
    if (boxSize > data.length - offset) return null;
    offset += boxSize;
  }
  return null;
}

/// Pulls the audio configuration out of a `moov` box: sample entry, the
/// AudioSpecificConfig, sample sizes and chunk offsets.
void _dumpMoov(Uint8List moov, int base) {
  final trak = _child(moov, 'trak');
  if (trak == null) {
    print('  no trak');
    return;
  }
  final mdia = _child(trak, 'mdia');
  final minf = mdia == null ? null : _child(mdia, 'minf');
  final stbl = minf == null ? null : _child(minf, 'stbl');
  if (stbl == null) {
    print('  no stbl');
    return;
  }

  final hdlr = _child(mdia!, 'hdlr');
  if (hdlr != null && hdlr.length > 12) {
    print('  handler: ${String.fromCharCodes(hdlr.sublist(8, 12))}');
  }

  final stsd = _child(stbl, 'stsd');
  if (stsd != null && stsd.length > 8) {
    final count = _u32(stsd, 4);
    print('  stsd entries: $count');
    if (stsd.length > 16) {
      final entrySize = _u32(stsd, 8);
      final entryType = String.fromCharCodes(stsd.sublist(12, 16));
      print('  entry: $entryType size=$entrySize');
      // AudioSampleEntry fields live 24 bytes into the entry body:
      // 6 reserved + 2 dri + 2 version + 2 revision + 4 vendor, then
      // 2 channels + 2 sample size + 2 compression + 2 packet + 4 rate(16.16).
      if (stsd.length >= 44) {
        final channels = _u16(stsd, 32);
        final sampleSize = _u16(stsd, 34);
        final sampleRate = _u32(stsd, 40) >> 16;
        print('  channels=$channels sampleSize=$sampleSize sampleRate=$sampleRate');
      }
      final esds = _findBytes(stsd, 'esds');
      if (esds != null) {
        final payload = stsd.sublist(esds + 4);
        final asc = _readAsc(payload);
        if (asc != null) {
          print('  ASC: ${_hex(asc)}  -> aot=${asc[0] >> 3} '
              'srIdx=${((asc[0] & 0x07) << 1) | (asc[1] >> 7)} '
              'chCfg=${(asc[1] >> 3) & 0x0F}');
        } else {
          print('  esds payload: ${_hex(Uint8List.fromList(payload.take(40).toList()))}');
        }
      }
    }
  }

  for (final box in ['stts', 'stsz', 'stsc', 'stco', 'co64', 'stss', 'elst']) {
    final body = _child(stbl, box);
    if (body == null) continue;
    final count = body.length >= 8 ? _u32(body, 4) : -1;
    print('  $box: ${body.length} bytes, entry count=$count');
    if (box == 'stsz' && body.length >= 12) {
      final sampleSize = _u32(body, 4);
      final sampleCount = _u32(body, 8);
      print('    fixedSampleSize=$sampleSize samples=$sampleCount');
      if (sampleSize == 0 && body.length >= 12 + 8) {
        final first = <int>[];
        for (var i = 0; i < 5 && 12 + i * 4 + 4 <= body.length; i++) {
          first.add(_u32(body, 12 + i * 4));
        }
        print('    first sample sizes: $first');
      }
    }
    if ((box == 'stco' || box == 'co64') && body.length >= 12) {
      final firstChunk = box == 'stco' ? _u32(body, 8) : _u64(body, 8);
      print('    first chunk offset: $firstChunk');
      if (body.length >= 16) {
        final second = box == 'stco' ? _u32(body, 12) : _u64(body, 12);
        print('    second chunk offset: $second');
      }
    }
    if (box == 'stsc' && body.length >= 20) {
      // first three run entries: firstChunk, samplesPerChunk, descIdx
      for (var i = 0; i < 3 && 8 + i * 12 + 12 <= body.length; i++) {
        print('    run $i: firstChunk=${_u32(body, 8 + i * 12)} '
            'spc=${_u32(body, 12 + i * 12)} desc=${_u32(body, 16 + i * 12)}');
      }
    }
  }
  print('  (moov at file offset $base)');
}

Uint8List? _child(Uint8List data, String type) {
  final found = _findBox(data, 0, type);
  if (found == null) return null;
  final start = found.$2;
  final length = found.$3;
  if (start + length > data.length) return null;
  return data.sublist(start, start + length);
}

/// Walks the MPEG-4 descriptor tree inside `esds` and returns the
/// AudioSpecificConfig (tag 0x05), which is what the ADTS header is built from.
///
/// Descriptor headers are `tag` + a base-128 length where every byte except the
/// last has the high bit set.
Uint8List? _readAsc(Uint8List data) {
  Uint8List? walk(Uint8List bytes, int from, int to, int depth) {
    var at = from;
    while (at < to && depth < 8) {
      final tag = bytes[at++];
      var length = 0;
      while (at < to) {
        final b = bytes[at++];
        length = (length << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      final end = (at + length).clamp(0, to);
      if (tag == 0x03) {
        // ES_Descriptor: ES_ID (2) + flags (1), then nested descriptors.
        final nested = walk(bytes, at + 3, end, depth + 1);
        if (nested != null) return nested;
      } else if (tag == 0x04) {
        // DecoderConfigDescriptor: objectType (1) + streamType (1) +
        // bufferSize (3) + maxBitrate (4) + avgBitrate (4), then nested.
        final nested = walk(bytes, at + 13, end, depth + 1);
        if (nested != null) return nested;
      } else if (tag == 0x05) {
        return Uint8List.sublistView(bytes, at, end);
      }
      at = end;
      if (length == 0 && tag == 0) break;
    }
    return null;
  }

  return walk(data, 0, data.length, 0);
}

int? _findBytes(Uint8List data, String ascii) {
  final needle = ascii.codeUnits;
  outer:
  for (var i = 0; i + needle.length <= data.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return null;
}

String _hex(Uint8List data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

int _u16(Uint8List d, int at) => (d[at] << 8) | d[at + 1];

int _u32(Uint8List d, int at) =>
    (d[at] << 24) | (d[at + 1] << 16) | (d[at + 2] << 8) | d[at + 3];

int _u64(Uint8List d, int at) =>
    (_u32(d, at) << 32) | _u32(d, at + 4);
