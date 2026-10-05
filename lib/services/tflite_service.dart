import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  Interpreter? _interpreter;
  bool _isLoaded = false;

  static const List<String> labels = ['Pointing', 'Close', 'Open'];

  bool get isLoaded => _isLoaded;

  Future<bool> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/keypoint_classifier.tflite');
      _isLoaded = true;
      debugPrint('Loaded keypoint_classifier.tflite successfully.');
      return true;
    } catch (e) {
      try {
        _interpreter = await Interpreter.fromAsset('assets/models/hand_sign_keypoints.tflite');
        _isLoaded = true;
        debugPrint('Loaded hand_sign_keypoints.tflite successfully.');
        return true;
      } catch (e2) {
        debugPrint('Error loading keypoint classifier model: $e2');
        _isLoaded = false;
        return false;
      }
    }
  }

  static String getLabel(int index) {
    if (index >= 0 && index < labels.length) {
      return labels[index];
    }
    return 'Unknown ($index)';
  }

  /// Runs inference on 42 preprocessed features and returns predicted class (0=Pointing, 1=Close, 2=Open).
  int predict(List<double> features42) {
    if (_interpreter == null || !_isLoaded) {
      return -1;
    }

    if (features42.length != 42) {
      debugPrint('Error: Input feature length expected 42, got ${features42.length}');
      return -1;
    }

    try {
      final input = [features42];

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final int numClasses = outputShape.last;
      final output = List.generate(1, (_) => List<double>.filled(numClasses, 0.0));

      _interpreter!.run(input, output);

      final List<double> logits = output[0];
      int maxIndex = 0;
      double maxVal = logits[0];
      for (int i = 1; i < logits.length; i++) {
        if (logits[i] > maxVal) {
          maxVal = logits[i];
          maxIndex = i;
        }
      }
      return maxIndex;
    } catch (e) {
      debugPrint('Error running TFLite keypoint classifier prediction: $e');
      return -1;
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
