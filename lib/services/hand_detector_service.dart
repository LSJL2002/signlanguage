import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'mediapipe_service.dart';
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
  final MediaPipeService _mediaPipeService = MediaPipeService();
  final TFLiteService _classifierService = TFLiteService();
  bool _isInitialized = false;

  Future<void> init() async {
    try {
      await _mediaPipeService.initHandLandmarker();
      await _classifierService.loadModel();
      _isInitialized = true;
      debugPrint('HandDetectorService initialized successfully.');
    } catch (e) {
      debugPrint('Error initializing HandDetectorService: $e');
    }
  }

  /// Processes live camera frame and returns real-time MediaPipe hand keypoints & sign prediction
  Future<HandAnalysisDebugResult> processLiveFrame({
    required CameraImage image,
    required int rotationDegrees,
    required bool isFrontCamera,
  }) async {
    final List<HandDebugLog> logs = [];

    if (!_isInitialized) {
      await init();
    }

    try {
      final landmarks21 = await _mediaPipeService.detectHandLandmarks(
        image: image,
        rotationDegrees: rotationDegrees,
        isFrontCamera: isFrontCamera,
      );

      if (landmarks21 == null || landmarks21.length < 21) {
        return HandAnalysisDebugResult(
          hasHand: false,
          predictedSign: -1,
          predictedLabel: 'No hand detected',
          logs: logs,
        );
      }

      final features42 = HandPreprocessor.preprocess(landmarks21, 1.0, 1.0);

      if (features42 == null) {
        return HandAnalysisDebugResult(
          hasHand: true,
          predictedSign: -1,
          predictedLabel: 'Preprocessing failed',
          landmarks: landmarks21,
          logs: logs,
        );
      }

      final int prediction = _classifierService.predict(features42);
      final String label = TFLiteService.getLabel(prediction);

      return HandAnalysisDebugResult(
        hasHand: true,
        predictedSign: prediction,
        predictedLabel: label,
        landmarks: landmarks21,
        logs: logs,
      );
    } catch (e) {
      return HandAnalysisDebugResult(
        hasHand: false,
        predictedSign: -1,
        predictedLabel: 'Error',
        logs: logs,
      );
    }
  }

  Future<HandAnalysisDebugResult> analyzeImageFile(String imagePath) async {
    final List<HandDebugLog> logs = [];

    if (!_isInitialized) {
      await init();
    }

    try {
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
        details: 'SUCCESS: Loaded photo file (${await file.length()} bytes).',
        success: true,
      ));

      final landmarks21 = await _mediaPipeService.detectHandLandmarksFromFile(imagePath);

      if (landmarks21 == null || landmarks21.length < 21) {
        logs.add(HandDebugLog(
          stage: '2. MediaPipe Hand Landmark',
          details: 'RESULT: No hand detected by MediaPipe HandLandmarker.',
          success: false,
        ));
        return HandAnalysisDebugResult(
          hasHand: false,
          predictedSign: -1,
          predictedLabel: 'No hand detected',
          logs: logs,
        );
      }

      final double wristX = landmarks21[0]['x'] ?? 0.0;
      final double wristY = landmarks21[0]['y'] ?? 0.0;

      logs.add(HandDebugLog(
        stage: '2. MediaPipe Hand Landmark',
        details: 'SUCCESS: Extracted 21 HAND keypoints. Wrist: (${wristX.toStringAsFixed(2)}, ${wristY.toStringAsFixed(2)})',
        success: true,
      ));

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
    _mediaPipeService.close();
    _classifierService.close();
    _isInitialized = false;
  }
}
