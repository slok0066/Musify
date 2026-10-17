// Scratch verification: does DESedeEngine(K repeated 3x) == single DES
// for the JioSaavn encrypted_media_url payload?
// Run: dart run tool/des_check.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const encrypted = 'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDy8nVlJ30W/JWSHLJuuQw3aQwm7MpPuw33buRfgf8pZQ4/IwtEzJQ4+Rw7tS9a8Gtq';
const expected = 'https://aac.saavncdn.com/423/852ad6cc81d7733c5e9bfc46d7b063e2_96.mp4';

String? decrypt(String input, List<int> keyBytes) {
  try {
    var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final data = base64.decode(normalized);
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      ECBBlockCipher(DESedeEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
        KeyParameter(Uint8List.fromList(keyBytes)),
        null,
      ),
    );
    final out = cipher.process(Uint8List.fromList(data));
    return utf8.decode(out, allowMalformed: true);
  } catch (e) {
    return 'ERR: $e';
  }
}

void main() {
  final key8 = utf8.encode('38346591');
  final key24 = [...key8, ...key8, ...key8];

  final single = decrypt(encrypted, key8);
  final triple = decrypt(encrypted, key24);

  print('key8  -> $single');
  print('key24 -> $triple');
  print('expected -> $expected');
  print('');
  print('8-byte key result == expected : ${single == expected}');
  print('24-byte key result == expected: ${triple == expected}');
}
