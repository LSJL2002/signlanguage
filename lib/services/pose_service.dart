import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Independent from the hand classifier and its 42-feature input.
typedef Landmark = Map<String, double>;

class TrackedHand {
  const TrackedHand(this.side, this.confidence, this.landmarks);
  final String side;
  final double confidence;
  final List<Landmark> landmarks;
  static TrackedHand? parse(dynamic value, String expectedSide) {
    if (value is! Map || value['handedness'] != expectedSide) return null;
    final score = (value['confidence'] as num?)?.toDouble() ?? 0;
    final points = parsePoints(value['landmarks']);
    if (!score.isFinite || score < .6 || points.length != 21) return null;
    return TrackedHand(expectedSide, score, points);
  }
}

List<Landmark> parsePoints(dynamic raw) => (raw as List? ?? [])
    .map(
      (point) => (point as Map).map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
    )
    .toList();

class TrackingFrame {
  const TrackingFrame({
    required this.frameId,
    required this.timestampUs,
    required this.body,
    this.face = const [],
    this.leftHand,
    this.rightHand,
  });
  final int frameId;
  final int timestampUs;
  final List<Landmark> body;
  final List<Landmark> face;
  final TrackedHand? leftHand;
  final TrackedHand? rightHand;
  factory TrackingFrame.fromMap(Map raw) {
    debugPrint(
      'KSL_RECV frameId=${raw['frameId']} face landmark count=${(raw['face'] as List?)?.length ?? 0}',
    );
    final frame = TrackingFrame(
      frameId: raw['frameId'] as int,
      timestampUs: raw['timestampUs'] as int,
      body: parsePoints(raw['body']),
      face: parsePoints(raw['face']),
      leftHand: TrackedHand.parse(raw['leftHand'], 'Left'),
      rightHand: TrackedHand.parse(raw['rightHand'], 'Right'),
    );
    debugPrint(
      'KSL_PARSE frameId=${frame.frameId} face landmark count=${frame.face.length} first=${frame.face.isEmpty ? null : frame.face.first}',
    );
    return frame;
  }
}

class PoseService {
  static const channel = MethodChannel('com.example.signlanguage/pose');
  bool _ready = false;
  bool _closed = false;
  bool _inFlight = false;
  int _generation = 0;
  String? error;

  Future<void> initialize() async {
    _closed = false;
    _ready = false;
    final generation = ++_generation;
    try {
      final ready = await channel.invokeMethod<bool>('initialize') ?? false;
      if (_closed || generation != _generation) return;
      _ready = ready;
      error = ready ? null : 'Body tracking unavailable';
    } catch (e) {
      error = 'Body tracking unavailable';
    }
  }

  Future<TrackingFrame?> detect(
    CameraImage image, {
    required int rotation,
    required bool mirror,
    required int frameId,
    required int timestampUs,
  }) async {
    if (!_ready || _closed || _inFlight) return null;
    if (image.planes.length != 3) {
      error = 'Body tracking requires YUV420 frames';
      return null;
    }
    _inFlight = true;
    final generation = _generation;
    final p = image.planes;
    try {
      final raw = await channel.invokeMapMethod<dynamic, dynamic>('detect', {
        'frameId': frameId,
        'timestampUs': timestampUs,
        'width': image.width,
        'height': image.height,
        'y': p[0].bytes,
        'u': p[1].bytes,
        'v': p[2].bytes,
        'yStride': p[0].bytesPerRow,
        'uStride': p[1].bytesPerRow,
        'vStride': p[2].bytesPerRow,
        'uPixelStride': p[1].bytesPerPixel ?? 1,
        'vPixelStride': p[2].bytesPerPixel ?? 1,
        'rotation': rotation,
        'mirror': mirror,
      });
      debugPrint(
        'KSL_CHANNEL frameId=${raw?['frameId']} face landmark count=${(raw?['face'] as List?)?.length ?? 0}',
      );
      error = null;
      if (_closed ||
          generation != _generation ||
          raw == null ||
          raw['frameId'] != frameId ||
          raw['timestampUs'] != timestampUs) {
        return null;
      }
      return TrackingFrame.fromMap(raw);
    } catch (e) {
      debugPrint('KSL_RECV failure: $e');
      error = 'Body tracking unavailable';
      return null;
    } finally {
      _inFlight = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _generation++;
    _ready = false;
    try {
      await channel.invokeMethod<void>('close');
    } catch (_) {}
  }
}

int poseRotation(
  int sensorOrientation,
  DeviceOrientation orientation,
  bool front,
) {
  final degrees = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return (sensorOrientation + (front ? degrees : -degrees) + 360) % 360;
}
