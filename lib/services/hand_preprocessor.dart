import 'dart:math' as math;

class HandPreprocessor {
  /// Preprocesses 21 2D hand keypoint landmarks into 42 float32 input features for the TFLite model.
  ///
  /// Steps:
  /// 1. Convert normalized x/y [0, 1] to pixel x/y using image width and height.
  /// 2. Subtract wrist landmark (landmark 0) from all landmarks (making wrist the origin).
  /// 3. Calculate max Euclidean distance from wrist across all 21 landmarks.
  /// 4. Divide all (x, y) relative coordinates by max distance.
  /// 5. Flatten the 21 (x, y) coordinates into a 42-element float List.
  static List<double>? preprocess(
    List<Map<String, double>> landmarks,
    double imageWidth,
    double imageHeight,
  ) {
    if (landmarks.length < 21) return null;

    // Step 1: Convert normalized coordinates to pixel coordinates
    final List<double> pixelX = List.filled(21, 0.0);
    final List<double> pixelY = List.filled(21, 0.0);

    for (int i = 0; i < 21; i++) {
      pixelX[i] = landmarks[i]['x']! * imageWidth;
      pixelY[i] = landmarks[i]['y']! * imageHeight;
    }

    // Step 2: Wrist origin subtraction (wrist is landmark 0)
    final double wristX = pixelX[0];
    final double wristY = pixelY[0];

    final List<double> relX = List.filled(21, 0.0);
    final List<double> relY = List.filled(21, 0.0);

    for (int i = 0; i < 21; i++) {
      relX[i] = pixelX[i] - wristX;
      relY[i] = pixelY[i] - wristY;
    }

    // Step 3: Find max Euclidean distance from wrist
    double maxDist = 0.0;
    for (int i = 0; i < 21; i++) {
      final double dist = math.sqrt(relX[i] * relX[i] + relY[i] * relY[i]);
      if (dist > maxDist) {
        maxDist = dist;
      }
    }

    if (maxDist == 0) maxDist = 1.0;

    // Steps 4 & 5: Normalize and flatten to 42 float values
    final List<double> features = List.filled(42, 0.0);
    for (int i = 0; i < 21; i++) {
      features[i * 2] = relX[i] / maxDist;
      features[i * 2 + 1] = relY[i] / maxDist;
    }

    return features;
  }
}
