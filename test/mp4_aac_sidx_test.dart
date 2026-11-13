import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/media_cache.dart';
import 'package:musify/services/mp4_aac.dart';

void main() {
  test('Mp4AacIndex parses sidx and seeks instantly', () async {
    final dio = Dio();
    final res = await dio.get<List<int>>(
      'https://yt.chocolatemoo53.com/latest_version?id=SnislRBOMA4&itag=140',
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Range': 'bytes=0-8191'},
        followRedirects: true,
      ),
    );
    final bytes = Uint8List.fromList(res.data!);
    final index = Mp4AacIndex.parse(bytes, fileLength: 1942739);
    expect(index, isNotNull);
    expect(index!.isFragmented, isTrue);
    expect(index.sidxFragments, isNotNull);
    expect(index.sidxFragments!.length, 12);
    expect(index.duration.inSeconds, inInclusiveRange(117, 120));

    // Initially at Fragment 0 (0 to ~10s)
    expect(index.baseTime, Duration.zero);
    final t0 = index.timeAtAdtsOffset(0);
    expect(t0, Duration.zero);
    final off0 = index.adtsOffsetAtTime(Duration.zero);
    expect(off0, 0);

    // Seek to 45 seconds using a mock StreamSession
    final mockSession = _MockStreamSession(url: 'https://yt.chocolatemoo53.com/latest_version?id=SnislRBOMA4&itag=140', total: 1942739);
    await index.ensureCoveredTime(const Duration(seconds: 45), mockSession);

    // Should be anchored at Fragment 4 (starts at ~39.9s)
    expect(index.baseTime.inSeconds, inInclusiveRange(39, 40));
    final t45 = index.timeAtAdtsOffset(index.adtsOffsetAtTime(const Duration(seconds: 45)));
    expect((t45 - const Duration(seconds: 45)).inMilliseconds.abs(), lessThan(50));

    final w = index.windowAt(index.adtsOffsetAtTime(const Duration(seconds: 45)), 32768);
    expect(w.fileStart, greaterThan(647445)); // inside Fragment 4's mdat
  });
}

class _MockStreamSession implements StreamSession {
  _MockStreamSession({required this.url, required this.total});
  final String url;
  @override
  final int total;
  final Dio _dio = Dio();
  int? jumpedTo;

  @override
  bool get isComplete => false;
  @override
  bool get isLive => true;
  @override
  String? get path => null;
  @override
  int get bytesAvailable => 0;
  @override
  String? get error => null;

  @override
  void jumpTo(int offset, [int? end]) {
    jumpedTo = offset;
  }

  @override
  Future<Uint8List?> read(int start, int end) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Range': 'bytes=$start-${end - 1}'},
        followRedirects: true,
      ),
    );
    return Uint8List.fromList(res.data!);
  }

  @override
  void release() {}
}
