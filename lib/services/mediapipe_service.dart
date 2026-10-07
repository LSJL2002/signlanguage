import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MediaPipeService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.signlanguage/mediapipe',
  );

  Future<bool> initHandLandmarker() async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        'initHandLandmarker',
      );
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error initializing MediaPipe HandLandmarker: $e');
      return false;
    }
  }

  Future<List<Map<String, double>>?> detectHandLandmarksFromFile(
    String filePath,
  ) async {
    try {
      final List<dynamic>? rawLandmarks = await _channel
          .invokeMethod<List<dynamic>>('detectHandLandmarksFromFile', {
            'filePath': filePath,
          });

      if (rawLandmarks == null || rawLandmarks.isEmpty) {
        return null;
      }

      // Compatibility adapter: old classifier still receives one 21-point hand.
      // Native response retains both hands and handedness; never flatten to 75 points.
      final points = (rawLandmarks.first as Map)['landmarks'] as List;
      return points.map((item) {
        final Map<dynamic, dynamic> map = item as Map<dynamic, dynamic>;
        return {
          'x': (map['x'] as num).toDouble(),
          'y': (map['y'] as num).toDouble(),
          'z': (map['z'] as num).toDouble(),
        };
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('Error running MediaPipe HandLandmarker on file: $e');
      return null;
    }
  }

  Future<List<Map<String, double>>?> detectHandLandmarks({
    required CameraImage image,
    required int rotationDegrees,
    required bool isFrontCamera,
  }) async {
    try {
      if (image.planes.length < 3) return null;

      final Plane yPlane = image.planes[0];
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];

      final Map<String, dynamic> arguments = {
        'yBuffer': yPlane.bytes,
        'uBuffer': uPlane.bytes,
        'vBuffer': vPlane.bytes,
        'width': image.width,
        'height': image.height,
        'yRowStride': yPlane.bytesPerRow,
        'uvRowStride': uPlane.bytesPerRow,
        'uvPixelStride': uPlane.bytesPerPixel ?? 1,
        'rotationDegrees': rotationDegrees,
        'isFrontCamera': isFrontCamera,
      };

      final List<dynamic>? rawLandmarks = await _channel
          .invokeMethod<List<dynamic>>('detectHandLandmarks', arguments);

      if (rawLandmarks == null || rawLandmarks.isEmpty) {
        return null;
      }

      // Compatibility adapter: old classifier still receives one 21-point hand.
      // Native response retains both hands and handedness; never flatten to 75 points.
      final points = (rawLandmarks.first as Map)['landmarks'] as List;
      return points.map((item) {
        final Map<dynamic, dynamic> map = item as Map<dynamic, dynamic>;
        return {
          'x': (map['x'] as num).toDouble(),
          'y': (map['y'] as num).toDouble(),
          'z': (map['z'] as num).toDouble(),
        };
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('Error running MediaPipe HandLandmarker on live frame: $e');
      return null;
    }
  }

  Future<void> close() async {
    try {
      await _channel.invokeMethod('closeHandLandmarker');
    } catch (_) {}
  }
}
