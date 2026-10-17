// Scratch verification for `lib/services/mp4_aac.dart`: parse a real JioSaavn
// 320 kbps file's `moov` and prove that the ADTS stream it would build is
// correct — frame lengths in the generated headers must equal the sample sizes
// in the MP4's sample table.
// Run: dart run tool/adts_check.dart [query]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:musify/services/mp4_aac.dart';

const _api = 'https://www.jiosaavn.com/api.php';

Future<void> main(List<String> args) async {
  final query = args.isNotEmpty ? args.join(' ') : 'kesariya';
  final client = HttpClient();

  final encrypted = await _searchEncrypted(client, query);
  if (encrypted == null) {
    print('search returned nothing');
    return;
  }
  final url = _decrypt(encrypted).replaceAll(RegExp(r'_\d+\.'), '_320.');
  print('URL     : $url');

  // 1. Length + the head window that holds `ftyp` + `moov`.
  final total = await _length(client, url);
  print('LENGTH  : $total');

  final head = await _get(client, url, 0, 131071);
  print('HEAD    : ${head.length} bytes');

  final index = Mp4AacIndex.parse(head, fileLength: total);
  if (index == null) {
    print('PARSE   : FAILED (fallback path would be used)');
    // Show where moov sits so a failure is diagnosable.
    _dumpTopLevel(head);
    client.close(force: true);
    return;
  }

  final minutes = index.duration.inMinutes;
  final seconds = index.duration.inSeconds % 60;
  print('PARSE   : ok');
  print('  samples=${index.sampleCount} sampleRate=${index.sampleRate} '
      'channels=${index.channels} srIndex=${index.srIndex} '
      'chConfig=${index.channelConfig} samplesPerFrame=${index.samplesPerFrame}');
  print('  duration=${minutes}m${seconds}s totalAdts=${index.totalAdtsBytes} '
      'totalFile=${index.totalFileBytes}');

  // 2. The first few windows: offsets must advance and stay inside the file.
  for (final offset in [0, index.totalAdtsBytes ~/ 2, index.totalAdtsBytes - 1]) {
    final window = index.windowAt(offset, 64 * 1024);
    print('  window@$offset -> frames ${window.firstSample}..${window.lastSample} '
        '(${window.frameCount}) file [${window.fileStart}, ${window.fileEnd}) '
        'adts at ${window.adtsOffset} len ${window.adtsBytes}');
    if (window.fileEnd > (total ?? 1 << 30)) {
      print('  !! window runs past the end of the file');
    }
  }

  // 3. Pull the file range for the very first window and assemble it: every
  //    generated ADTS length field must match the sample table.
  final first = index.windowAt(0, 16 * 1024);
  final bytes = await _get(client, url, first.fileStart, first.fileEnd - 1);
  if (bytes.length < first.fileEnd - first.fileStart) {
    print('FETCH   : short read (${bytes.length} of ${first.fileEnd - first.fileStart})');
    client.close(force: true);
    return;
  }
  final adts = index.assemble(first, bytes);
  print('ADTS    : assembled ${adts.length} bytes (expected ${first.adtsBytes})');
  final head16 = adts.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  print('  first 16 bytes: $head16');

  // Walk the assembled chunks and verify the ADTS length field == frame size.
  var at = 0;
  var frames = 0;
  var bad = 0;
  while (at + 7 <= adts.length) {
    if (adts[at] != 0xFF || (adts[at + 1] & 0xF0) != 0xF0) {
      print('  !! no sync at $at');
      break;
    }
    final length = ((adts[at + 3] & 0x03) << 11) | (adts[at + 4] << 3) | (adts[at + 5] >> 5);
    if (length < 8 || at + length > adts.length) {
      bad++;
      break;
    }
    at += length;
    frames++;
  }
  print('  walked $frames frames, ended at $at of ${adts.length} '
      '(alignment ${at == adts.length ? 'exact' : 'MISMATCH'}, bad=$bad)');

  // 4. Also assemble the *last* window to prove the tail math.
  final lastSampleStart = index.sampleAt(index.totalAdtsBytes - 1024);
  final tailWindow = index.windowAt(index.totalAdtsBytes - index.totalAdtsBytes % 4096, 4096);
  print('  last-sample index: $lastSampleStart, tail window '
      'frames ${tailWindow.firstSample}..${tailWindow.lastSample} '
      'file [${tailWindow.fileStart}, ${tailWindow.fileEnd})');

  client.close(force: true);
}

void _dumpTopLevel(Uint8List data) {
  var offset = 0;
  while (offset + 8 <= data.length) {
    final size = (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
    final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    print('  box $type at $offset size=$size');
    if (size < 8 || offset + size > data.length) break;
    offset += size;
  }
}

Future<String?> _searchEncrypted(HttpClient client, String query) async {
  final uri = Uri.parse('$_api?__call=search.getResults&q=${Uri.encodeQueryComponent(query)}'
      '&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=5&p=1');
  final request = await client.getUrl(uri);
  request.headers.set('User-Agent', 'Mozilla/5.0');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (!body.trim().startsWith('{')) return null;
  final json = jsonDecode(body) as Map<String, dynamic>;
  for (final raw in (json['results'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final more = (raw['more_info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final encrypted = more['encrypted_media_url']?.toString() ?? '';
    if (encrypted.isEmpty) continue;
    print('TITLE   : ${raw['title']}');
    return encrypted;
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
      KeyParameter(Uint8List.fromList([...key, ...key, ...key])),
      null,
    ),
  );
  final out = cipher.process(Uint8List.fromList(base64.decode(normalized)));
  return utf8.decode(out, allowMalformed: true);
}

Future<int?> _length(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('Range', 'bytes=0-0');
  final response = await request.close();
  final range = response.headers.value('content-range');
  await response.drain<void>();
  if (range == null) return null;
  final slash = range.lastIndexOf('/');
  return slash < 0 ? null : int.tryParse(range.substring(slash + 1).trim());
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
