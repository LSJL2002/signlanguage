import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'pose_service.dart';
import 'sequence_preprocessor.dart';
import 'stage1_input_adapter.dart';

/// Raw per-frame scores only. No gloss decoding or Stage 2 processing.
class Stage1Result {
  Stage1Result(this.inputShape, this.outputShape, this.logits);

  final List<int> inputShape;
  final List<int> outputShape;
  final List<List<List<double>>> logits;
}

/// Independent sequence inference; does not replace the 42-feature classifier.
class Stage1InferenceService {
  Stage1InferenceService._(this._interpreter);

  static const modelAsset = 'assets/models/stage1_model_float32.tflite';
  final Interpreter _interpreter;
  bool _closed = false;

  static Future<Stage1InferenceService> load({
    String asset = modelAsset,
  }) async {
    late final Interpreter interpreter;
    try {
      interpreter = await Interpreter.fromAsset(asset);
    } catch (error, stack) {
      debugPrint('KSL_STAGE1 load/allocate model=$asset error=$error\n$stack');
      rethrow;
    }
    try {
      if (interpreter.getInputTensors().length != 1 ||
          interpreter.getOutputTensors().length != 1) {
        throw StateError('Stage 1 requires one input and one output tensor.');
      }
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      if ((input.type != TensorType.float16 &&
              input.type != TensorType.float32) ||
          output.type != input.type ||
          input.shape.length != 3 ||
          input.shape[0] != 1 ||
          input.shape[1] != 492 ||
          output.shape.length != 3 ||
          output.shape.last != 2358) {
        throw StateError('Unexpected Stage 1 tensor contract.');
      }
      return Stage1InferenceService._(interpreter);
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  Stage1Result inferTrackingFrames(List<TrackingFrame> frames) =>
      inferPreprocessed(SequencePreprocessor.fromTrackingFrames(frames));

  /// Accepts mapped Pose 11 + Face 70 + Right Hand 21 + Left Hand 21 frames.
  Stage1Result inferLandmarks(List<List<Landmark?>> frames) =>
      inferPreprocessed(SequencePreprocessor.preprocess(frames));

  Stage1Result inferPreprocessed(List<List<List<double>>> sequence) {
    if (_closed) throw StateError('Stage 1 interpreter is closed.');
    final type = _interpreter.getInputTensor(0).type;
    final float32 = type == TensorType.float32;
    final elementBytes = float32 ? 4 : 2;
    final input = Stage1InputAdapter.adapt(
      sequence,
      dtype: float32 ? Stage1InputDtype.float32 : Stage1InputDtype.float16,
    );
    final expectedOutput = [1, sequence.length, 2358];
    try {
      if (!listEquals(_interpreter.getInputTensor(0).shape, input.shape)) {
        _interpreter.resizeInputTensor(0, input.shape);
        _interpreter.allocateTensors();
      }
      final tensor = _interpreter.getInputTensor(0);
      if (!listEquals(tensor.shape, input.shape) ||
          tensor.numBytes() != input.bytes.length) {
        throw StateError(
          'Stage 1 input allocation does not match ${input.shape}.',
        );
      }
      debugPrint(
        'KSL_STAGE1 allocated input=${tensor.shape} dtype=${tensor.type}',
      );
      tensor.setTo(input.bytes);
      _interpreter.invoke();
      // Dynamic outputs must be queried AFTER invoke, not from initial metadata.
      final output = _interpreter.getOutputTensor(0);
      if (!listEquals(output.shape, expectedOutput) ||
          output.type != type ||
          output.numBytes() != sequence.length * 2358 * elementBytes) {
        throw StateError(
          'Stage 1 output ${output.shape}; expected $expectedOutput.',
        );
      }
      final bytes = ByteData.sublistView(output.data);
      final logits = [
        List.generate(
          sequence.length,
          (t) => List.generate(2358, (c) {
            if (float32) {
              final value = bytes.getFloat32((t * 2358 + c) * 4, Endian.host);
              if (!value.isFinite) {
                throw StateError(
                  'Non-finite Stage 1 output at frame=$t class=$c.',
                );
              }
              return value;
            }
            final bits = bytes.getUint16((t * 2358 + c) * 2, Endian.host);
            final exponent = (bits >> 10) & 31;
            final fraction = bits & 1023;
            if (exponent == 31) {
              throw StateError(
                'Non-finite Stage 1 output at frame=$t class=$c.',
              );
            }
            final magnitude = exponent == 0
                ? fraction / 16777216
                : (1 + fraction / 1024) * math.pow(2, exponent - 15);
            return (bits & 0x8000) == 0
                ? magnitude.toDouble()
                : -magnitude.toDouble();
          }),
        ),
      ];
      return Stage1Result(
        List<int>.unmodifiable(tensor.shape),
        List<int>.unmodifiable(output.shape),
        logits,
      );
    } catch (error, stack) {
      debugPrint('KSL_STAGE1 input=${input.shape} error=$error\n$stack');
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _interpreter.close();
    _closed = true;
  }
}
