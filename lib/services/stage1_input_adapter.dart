import 'dart:math' as math;
import 'dart:typed_data';

enum Stage1InputDtype { float16, float32 }

/// Packed floating-point tensor. Resize the interpreter input to [shape] before
/// allocating tensors and passing [bytes] to TFLite. No inference is run here.
class Stage1Input {
  Stage1Input._(int frames, this.bytes)
    : shape = List<int>.unmodifiable([1, 492, frames]);

  final List<int> shape;
  final Uint8List bytes;
}

/// Model boundary only: leaves SequencePreprocessor and its NaNs unchanged.
class Stage1InputAdapter {
  static Stage1Input adapt(
    List<List<List<double>>> sequence, {
    Stage1InputDtype dtype = Stage1InputDtype.float16,
  }) {
    final frames = sequence.length;
    if (frames < 1 || frames > 3000) {
      throw ArgumentError(
        'Stage 1 requires 1–3000 frames; no implicit trimming.',
      );
    }
    for (final frame in sequence) {
      if (frame.length != 123 || frame.any((point) => point.length != 4)) {
        throw ArgumentError('Expected [T,123,4] with [x,y,dx,dy] per point.');
      }
    }
    final elementBytes = dtype == Stage1InputDtype.float32 ? 4 : 2;
    final data = ByteData(492 * frames * elementBytes);
    final scratch = ByteData(8);
    for (var t = 0; t < frames; t++) {
      for (var p = 0; p < 123; p++) {
        for (var f = 0; f < 4; f++) {
          // Flatten landmark-major, then transpose time and feature axes.
          final offset = ((p * 4 + f) * frames + t) * elementBytes;
          final value = sequence[t][p][f];
          if (dtype == Stage1InputDtype.float32) {
            data.setFloat32(offset, value.isFinite ? value : 0.0, Endian.host);
            // A finite Dart double can overflow when converted to float32.
            if (!data.getFloat32(offset, Endian.host).isFinite) {
              data.setFloat32(offset, 0.0, Endian.host);
            }
          } else {
            data.setUint16(offset, _finiteFloat16(value, scratch), Endian.host);
          }
        }
      }
    }
    return Stage1Input._(frames, data.buffer.asUint8List());
  }

  /// IEEE 754 binary16, round to nearest with ties to even. Non-finite input
  /// and values that would round to infinity become positive zero.
  static int _finiteFloat16(double value, ByteData scratch) {
    if (!value.isFinite || value.abs() >= 65520) return 0;
    final sign = value.isNegative ? 0x8000 : 0;
    final magnitude = value.abs();
    if (magnitude == 0) return sign;
    scratch.setFloat64(0, magnitude, Endian.big);
    final exponent = ((scratch.getUint32(0, Endian.big) >> 20) & 0x7ff) - 1023;
    if (exponent < -14) {
      return sign | _roundEven(magnitude * 16777216); // Subnormal: 2^-24.
    }
    final significand = _roundEven(magnitude / math.pow(2, exponent - 10));
    // Addition naturally carries a rounded significand into the next exponent.
    return sign | (((exponent + 15) << 10) + significand - 1024);
  }

  static int _roundEven(double value) {
    final lower = value.floor();
    final remainder = value - lower;
    return remainder > 0.5 || (remainder == 0.5 && lower.isOdd)
        ? lower + 1
        : lower;
  }
}
