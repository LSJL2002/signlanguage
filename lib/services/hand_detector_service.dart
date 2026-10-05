import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'hand_preprocessor.dart';
import 'tflite_service.dart';

class HandDebugLog {
  final String stage;
  final String details;
  final bool success;

  HandDebugLog({
    required this.stage,
    required this.details,
    required this.success,
  });
}

class HandAnalysisDebugResult {
  final bool hasHand;
  final int predictedSign;
  final String predictedLabel;
  final List<Map<String, double>>? landmarks;
  final List<HandDebugLog> logs;

  HandAnalysisDebugResult({
    required this.hasHand,
    required this.predictedSign,
    required this.predictedLabel,
    this.landmarks,
    required this.logs,
  });
}

class HandDetectorService {
  late PoseDetector _poseDetector;
  final TFLiteService _classifierService = TFLiteService();
  bool _isInitialized = false;

  Future<void> init() async {
    try {
      _poseDetector = PoseDetector(options: PoseDetectorOptions());
      await _classifierService.loadModel();
      _isInitialized = true;
      debugPrint('HandDetectorService initialized successfully.');
    } catch (e) {
      debugPrint('Error initializing HandDetectorService: $e');
    }
  }

  Future<HandAnalysisDebugResult> analyzeImageFile(String imagePath) async {
    final List<HandDebugLog> logs = [];

    if (!_isInitialized) {
      await init();
    }

    try {
      // Step 1: Verify file
      final File file = File(imagePath);
      if (!await file.exists()) {
        logs.add(HandDebugLog(
          stage: '1. Image File',
          details: 'FAILED: File does not exist at $imagePath',
          success: false,
        ));
        return HandAnalysisDebugResult(
          hasHand: false,
          predictedSign: -1,
          predictedLabel: 'No image file',
          logs: logs,
        );
      }

      logs.add(HandDebugLog(
        stage: '1. Image File',
        details: 'SUCCESS: Image file loaded (${await file.length()} bytes).',
        success: true,
      ));

      // Step 2: Extract 2D keypoints using MediaPipe / MLKit
      final inputImage = InputImage.fromFilePath(imagePath);
      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isEmpty || poses.first.landmarks.isEmpty) {
        logs.add(HandDebugLog(
          stage: '2. 2D Keypoint Detection',
          details: 'RESULT: No pose / keypoints detected in image.',
          success: false,
        ));
        return HandAnalysisDebugResult(
          hasHand: false,
          predictedSign: -1,
          predictedLabel: 'No keypoints detected',
          logs: logs,
        );
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
        logs.add(HandDebugLog(
          stage: '2. 2D Keypoint Detection',
          details: 'RESULT: Less than 21 keypoints detected (${rawLandmarks.length}).',
          success: false,
        ));
        return HandAnalysisDebugResult(
          hasHand: false,
          predictedSign: -1,
          predictedLabel: 'Insufficient keypoints',
          logs: logs,
        );
      }

      final landmarks21 = rawLandmarks.sublist(0, 21);

      final double wristX = landmarks21[0]['x'] ?? 0.0;
      final double wristY = landmarks21[0]['y'] ?? 0.0;

      logs.add(HandDebugLog(
        stage: '2. 2D Keypoint Detection',
        details: 'SUCCESS: Extracted 21 keypoints. Wrist: (${wristX.toStringAsFixed(1)}, ${wristY.toStringAsFixed(1)})',
        success: true,
      ));

      // Step 3: Preprocess 21 keypoints to 42 float features
      final features42 = HandPreprocessor.preprocess(landmarks21, 1.0, 1.0);

      if (features42 == null) {
        logs.add(HandDebugLog(
          stage: '3. Preprocessing',
          details: 'FAILED: Feature preprocessing returned null.',
          success: false,
        ));
        return HandAnalysisDebugResult(
          hasHand: true,
          predictedSign: -1,
          predictedLabel: 'Preprocessing failed',
          landmarks: landmarks21,
          logs: logs,
        );
      }

      logs.add(HandDebugLog(
        stage: '3. Preprocessing',
        details: 'SUCCESS: Generated 42 float features relative to wrist origin.',
        success: true,
      ));

      // Step 4: Run keypoint_classifier.tflite (0=Pointing, 1=Close, 2=Open)
      final int prediction = _classifierService.predict(features42);
      final String label = TFLiteService.getLabel(prediction);

      logs.add(HandDebugLog(
        stage: '4. keypoint_classifier.tflite',
        details: prediction >= 0
            ? 'SUCCESS: Predicted Hand Sign = "$label" (class $prediction)'
            : 'FAILED: Classifier prediction failed.',
        success: prediction >= 0,
      ));

      return HandAnalysisDebugResult(
        hasHand: true,
        predictedSign: prediction,
        predictedLabel: label,
        landmarks: landmarks21,
        logs: logs,
      );
    } catch (e) {
      logs.add(HandDebugLog(
        stage: 'Error',
        details: 'Exception: $e',
        success: false,
      ));
      return HandAnalysisDebugResult(
        hasHand: false,
        predictedSign: -1,
        predictedLabel: 'Error',
        logs: logs,
      );
    }
  }

  void close() {
    _poseDetector.close();
    _classifierService.close();
    _isInitialized = false;
  }
}
