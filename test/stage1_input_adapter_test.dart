import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/stage1_input_adapter.dart';
import 'package:signlanguage/services/sequence_preprocessor.dart';

List<List<List<double>>> frames(int count) => List.generate(
  count,
  (_) => List.generate(123, (_) => List<double>.filled(4, 0)),
);

int word(Stage1Input input, int channel, int time) =>
    ByteData.sublistView(input.bytes)
        .getUint16((channel * input.shape[2] + time) * 2, Endian.host);

void main() {
  test(
    'float32 boundary preserves order and precision and sanitizes overflow',
    () {
      final source = frames(2);
      for (var t = 0; t < 2; t++) {
        for (var p = 0; p < 123; p++) {
          for (var f = 0; f < 4; f++) {
            source[t][p][f] = t + p / 128 + f / 4096;
          }
        }
      }
      source[0][0] = [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        double.maxFinite,
      ];
      final input = Stage1InputAdapter.adapt(
        source,
        dtype: Stage1InputDtype.float32,
      );
      expect(input.shape, [1, 492, 2]);
      expect(input.bytes.length, 492 * 2 * 4);
      final data = ByteData.sublistView(input.bytes);
      for (var t = 0; t < 2; t++) {
        for (var p = 0; p < 123; p++) {
          for (var f = 0; f < 4; f++) {
            expect(
              data.getFloat32(((p * 4 + f) * 2 + t) * 4, Endian.host),
              t == 0 && p == 0 ? 0.0 : source[t][p][f],
            );
          }
        }
      }
      expect(source[0][0][0], isNaN);
    },
  );

  test(
    'preserves every landmark/feature and transposes time into last axis',
    () {
      final source = frames(3);
      for (var t = 0; t < 3; t++) {
        for (var p = 0; p < 123; p++) {
          for (var f = 0; f < 4; f++) {
            source[t][p][f] = (t * 492 + p * 4 + f).toDouble();
          }
        }
      }
      final input = Stage1InputAdapter.adapt(source);
      expect(input.shape, [1, 492, 3]);
      expect(input.bytes.length, 1 * 492 * 3 * 2);
      for (var t = 0; t < 3; t++) {
        for (var p = 0; p < 123; p++) {
          for (var f = 0; f < 4; f++) {
            final bits = word(input, p * 4 + f, t);
            final exponent = (bits >> 10) & 31;
            final fraction = bits & 1023;
            final decoded = exponent == 0
                ? fraction / 16777216
                : (1024 + fraction) * (1 << exponent) / 33554432;
            expect(decoded, source[t][p][f]);
          }
        }
      }
    },
  );

  test(
    'float16 known encodings, ties, subnormals and overflow stay finite',
    () {
      final values = <double>[
        0,
        -0.0,
        1,
        -2,
        0.1,
        65504,
        65519,
        65520,
        -65520,
        double.maxFinite,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        1.00048828125,
        1.00146484375,
        0.00006103515625,
        0.000000059604644775390625,
        0.0000000298023223876953125,
        double.minPositive,
      ];
      final expected = [
        0x0000,
        0x8000,
        0x3c00,
        0xc000,
        0x2e66,
        0x7bff,
        0x7bff,
        0,
        0,
        0,
        0,
        0,
        0,
        0x3c00,
        0x3c02,
        0x0400,
        0x0001,
        0,
        0,
      ];
      final source = frames(1);
      for (var i = 0; i < values.length; i++) {
        source[0][i ~/ 4][i % 4] = values[i];
      }
      final input = Stage1InputAdapter.adapt(source);
      for (var i = 0; i < expected.length; i++) {
        expect(word(input, i, 0), expected[i], reason: 'value=${values[i]}');
      }
      expect(source[0][2][2].isNaN, isTrue);
    },
  );

  test('sanitizes never-observed preprocessed points without mutation', () {
    final sequence = SequencePreprocessor.preprocess([
      List.filled(123, null),
      List.filled(123, null),
    ]);
    expect(sequence[1][0][0], isNaN);
    final input = Stage1InputAdapter.adapt(sequence);
    expect(input.shape, [1, 492, 2]);
    expect(input.bytes.every((byte) => byte == 0), isTrue);
    expect(sequence[1][0][0], isNaN);
  });

  test('validates dimensions and rejects unsupported T without trimming', () {
    expect(() => Stage1InputAdapter.adapt([]), throwsArgumentError);
    expect(() => Stage1InputAdapter.adapt([[]]), throwsArgumentError);
    final malformed = frames(1);
    malformed[0][0] = [1, 2, 3];
    expect(() => Stage1InputAdapter.adapt(malformed), throwsArgumentError);
    final frame = frames(1).single;
    expect(Stage1InputAdapter.adapt(List.filled(3000, frame)).shape, [
      1,
      492,
      3000,
    ]);
    expect(
      () => Stage1InputAdapter.adapt(List.filled(3001, frame)),
      throwsArgumentError,
    );
  });
}
