// A seek must move the live transfer forward, not let every read that was
// already in flight drag it back to where playback used to be. That fight used
// to keep the target window unserved until the read timed out — the long
// buffering pause after moving the scrubber.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/media_cache.dart';

void main() {
  test('a stale read cannot yank the transfer back after a seek', () async {
    const total = 2 * 1024 * 1024;
    const oldStart = 900 * 1024;
    const target = 1400 * 1024;
    final data = Uint8List(total);
    data.setRange(0, 8, [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70]);

    final held = Completer<void>();
    final oldRequestSeen = Completer<void>();
    var jumped = false;
    final afterJump = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
      var start = 0;
      var end = total - 1;
      if (match != null) {
        start = int.parse(match.group(1)!);
        if (match.group(2)!.isNotEmpty) end = int.parse(match.group(2)!);
      }
      if (!jumped && start == oldStart) {
        // Hold the old window so its read cannot finish, then let the seek
        // prove that the old reader no longer drives the connection.
        if (!oldRequestSeen.isCompleted) oldRequestSeen.complete();
        await held.future;
      } else if (jumped) {
        afterJump.add(range ?? '');
      }
      try {
        req.response.statusCode = 206;
        req.response.headers
            .set('content-range', 'bytes $start-$end/$total');
        req.response.headers.set('content-type', 'application/octet-stream');
        req.response.headers.set('accept-ranges', 'bytes');
        final slice = data.sublist(start, end + 1);
        const chunk = 16 * 1024;
        var at = 0;
        while (at < slice.length) {
          final n = at + chunk <= slice.length ? chunk : slice.length - at;
          req.response.add(slice.sublist(at, at + n));
          await req.response.flush();
          at += n;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await req.response.close();
      } catch (_) {
        // The reader went away.
      }
    });

    final root = await Directory.systemTemp.createTemp('musify_seek_probe');
    final cache = MediaCache(Dio());
    await cache.useDirectories(
      cache: Directory('${root.path}/cache'),
      downloads: Directory('${root.path}/downloads'),
    );
    final url = 'http://127.0.0.1:${server.port}/song.mp4';
    final session = (await cache.openStream(
      url: url,
      fileName: 'song.m4a',
    ))!;
    expect(await session.read(0, 32 * 1024), isNotNull);

    // An old feed still waiting for its 192 KB window when the seek lands.
    final stale = session.read(oldStart, oldStart + 192 * 1024);
    await oldRequestSeen.future;

    jumped = true;
    session.jumpTo(target, target + 32 * 1024);
    final seekRead = await session
        .read(target, target + 32 * 1024)
        .timeout(const Duration(seconds: 5));
    expect(seekRead, hasLength(32 * 1024));

    // Give any stale steering a chance to fire; none may reach the old range.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      afterJump.where((r) => r.startsWith('bytes=$oldStart-')),
      isEmpty,
      reason: 'the pre-seek read must not move the connection back',
    );

    held.complete();
    await stale.timeout(const Duration(seconds: 2), onTimeout: () => null);
    session.release();
    await server.close(force: true);
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // A transfer handle can outlive the test process's cleanup.
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
