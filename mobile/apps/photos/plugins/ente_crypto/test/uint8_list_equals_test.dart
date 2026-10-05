import "dart:typed_data";

import "package:ente_crypto/src/uint8_list_equals.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("compares empty, byte-tail and complete-word lengths", () {
    for (final length in [0, 1, 7, 8, 9, 15, 16, 17]) {
      final a = Uint8List.fromList(
        List.generate(length, (index) => (index * 131 + 19) & 255),
      );
      final b = Uint8List.fromList(a);

      expect(uint8ListEquals(a, a), isTrue);
      expect(uint8ListEquals(a, b), isTrue);
      expect(uint8ListEquals(a, Uint8List(length + 1)), isFalse);

      for (var index = 0; index < length; index++) {
        b[index] ^= 0x80;
        expect(
          uint8ListEquals(a, b),
          isFalse,
          reason: "Mismatch at byte $index of $length",
        );
        b[index] ^= 0x80;
      }
    }
  });

  test(
    "respects unaligned nested view offsets and excludes surrounding bytes",
    () {
      final aBacking = Uint8List(40)..fillRange(0, 40, 0x55);
      final bBacking = Uint8List(48)..fillRange(0, 48, 0xAA);
      final a = Uint8List.sublistView(
        Uint8List.sublistView(aBacking, 1),
        2,
        19,
      );
      final b = Uint8List.sublistView(bBacking, 11, 28);
      for (var i = 0; i < a.length; i++) {
        a[i] = b[i] = (i * 17) & 255;
      }

      expect(uint8ListEquals(a, b), isTrue);
      for (final index in [0, 7, 8, 15, 16]) {
        b[index] ^= 1;
        expect(uint8ListEquals(a, b), isFalse, reason: "View byte $index");
        b[index] ^= 1;
      }
    },
  );
}
