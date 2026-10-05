import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'hand_preprocessor.dart';
import 'tflite_service.dart';

class HandAnalysisResult {
  final bool hasHand;
  final int predictedSign; // 0..5 or -1 if no hand
  final List<Map<String, double>>? landmarks;

  HandAnalysisResult({
    required this.hasHand,
    required this.predictedSign,
    this.landmarks,
  });
}

class HandAnalysisService {
  late PoseDetector _poseDetector;
  final TFLiteService _tfliteService = TFLiteService();
  bool _isInitialized = false;

  Future<void> init() async {
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
    await _tfliteService.loadModel();
    _isInitialized = true;
  }

  /// Analyzes an image file (photo/video frame) to extract 2D keypoints and predict 0~5 hand sign.
  Future<HandAnalysisResult> analyzeImageFile(String imagePath) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isEmpty || poses.first.landmarks.isEmpty) {
        return HandAnalysisResult(hasHand: false, predictedSign: -1);
      }

      final pose = poses.first;
      final rawLandmarks = <Map<String, double>>[];

      pose.landmarks.forEach((type, landmark) {
        rawLandmarks.add({
          'x': landmark.x,
          'y': landmark.y,
        });
      });

      if (rawLandmarks.length < 21) {
        return HandAnalysisResult(hasHand: false, predictedSign: -1);
      }

      final landmarks21 = rawLandmarks.sublist(0, 21);

      // Preprocess 21 2D keypoints into 42 float features
      final features42 = HandPreprocessor.preprocess(
        landmarks21,
        1.0,
        1.0,
      );

      if (features42 == null) {
        return HandAnalysisResult(hasHand: false, predictedSign: -1);
      }

      final int prediction = _tfliteService.predict(features42);

      return HandAnalysisResult(
        hasHand: true,
        predictedSign: prediction,
        landmarks: landmarks21,
      );
    } catch (e) {
      debugPrint('Error analyzing image file for 2D keypoints: $e');
      return HandAnalysisResult(hasHand: false, predictedSign: -1);
    }
  }

  void close() {
    if (_isInitialized) {
      _poseDetector.close();
      _tfliteService.close();
      _isInitialized = false;
    }
  }
}
