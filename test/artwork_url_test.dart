// Locks in the artwork rendition contract used by every cover in the app:
// move up to the CDN's biggest square size, never guess a URL that could 404.

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/core/artwork_url.dart';

void main() {
  test('JioSaavn thumbnails are upgraded to the biggest rendition', () {
    expect(hiresArtwork('https://c/x-150x150.jpg'), 'https://c/x-500x500.jpg');
    expect(hiresArtwork('http://c/x-50x50.webp'), 'https://c/x-500x500.webp');
    expect(hiresArtwork('https://c/x-150x150.jpg?cc=in'),
        'https://c/x-500x500.jpg?cc=in');
  });

  test('a cover already at the target size is left byte-for-byte', () {
    const url = 'https://c/x-500x500.jpg';
    expect(hiresArtwork(url), url);
  });

  test('foreign CDN shapes are never rewritten', () {
    const itunes = 'https://is1.mzstatic.com/image/thumb/x/600x600bb.jpg';
    const deezer =
        'https://e-cdns-images.dzcdn.net/images/cover/abc/500x500-000000-80-0-0.jpg';
    expect(hiresArtwork(itunes), itunes);
    expect(hiresArtwork(deezer), deezer);
  });

  test('urls without a rendition are passed through', () {
    expect(hiresArtwork('https://c/x.jpg'), 'https://c/x.jpg');
    expect(hiresArtwork(''), '');
    expect(hiresArtwork('   '), '');
  });
}
