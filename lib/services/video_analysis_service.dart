import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'hand_detector_service.dart';
import 'pose_service.dart';

/// Sequential sampling: timestamps describe requested sample times, not codec PTS.
class VideoAnalysisService {
  VideoAnalysisService({
    required this.classify,
    this.channel = PoseService.channel,
  });
  final HandAnalysisDebugResult Function(List<Landmark>?) classify;
  final MethodChannel channel;
  bool cancelled = false;
  static const intervalUs = 100000; // 10 FPS, independent of inference speed.
  static int sampleCount(int durationUs) =>
      (durationUs + intervalUs - 1) ~/ intervalUs;

  Future<File> analyze(
    String uri,
    File output,
    void Function(VideoAnalysisUpdate) onFrame,
  ) async {
    RandomAccessFile? writer;
    var stage = 'open video';
    final reference = Uri.parse(uri);
    debugPrint(
      'KSL_VIDEO_PICK Flutter uri=$uri content=${reference.scheme == 'content'} directFileAccess=${reference.scheme == 'content' ? 'not applicable; Android ContentResolver' : 'file reference'}',
    );
    try {
      final metadata = await channel.invokeMapMethod<String, dynamic>(
        'openVideo',
        {'uri': uri},
      );
      debugPrint('KSL_VIDEO_META Flutter $metadata');
      stage = 'read metadata';
      final duration = metadata?['durationUs'] as int? ?? 0;
      if (duration <= 0) throw StateError('Video duration unavailable');
      final total = sampleCount(duration);
      stage = 'open analysis output';
      writer = await output.open(mode: FileMode.write);
      await writer.writeString(
        '${jsonEncode({'type': 'metadata', 'version': 1, 'sourceUri': uri, 'durationUs': duration, 'sampleFps': 10, 'timestampKind': 'requestedSampleTimeUs', 'coordinates': 'upright normalized, unmirrored'})}\n',
      );
      for (var i = 0; i < total && !cancelled; i++) {
        final timestamp = i * intervalUs;
        stage = 'decode/analyze frame at ${timestamp ~/ 1000}ms';
        final raw = await channel.invokeMapMethod<String, dynamic>(
          'detectVideoFrame',
          {'frameId': i, 'timestampUs': timestamp},
        );
        if (cancelled) break;
        if (raw == null ||
            raw['frameId'] != i ||
            raw['timestampUs'] != timestamp) {
          throw StateError('Video frame identity mismatch');
        }
        stage = 'parse landmarks at ${timestamp ~/ 1000}ms';
        final frame = TrackingFrame.fromMap(raw);
        final selected = frame.rightHand ?? frame.leftHand;
        final classification = classify(selected?.landmarks);
        Map<String, dynamic>? hand(TrackedHand? h) => h == null
            ? null
            : {
                'landmarks': h.landmarks,
                'handedness': h.side,
                'confidence': h.confidence,
              };
        stage = 'save frame at ${timestamp ~/ 1000}ms';
        await writer.writeString(
          '${jsonEncode({
            'type': 'frame',
            'frameId': i,
            'timestampUs': timestamp,
            'body': frame.body,
            'face': frame.face,
            'leftHand': hand(frame.leftHand),
            'rightHand': hand(frame.rightHand),
            'classifierHand': selected?.side,
            'classification': {'hasHand': classification.hasHand, 'sign': classification.predictedSign, 'label': classification.predictedLabel},
          })}\n',
        );
        onFrame(
          VideoAnalysisUpdate(
            frame,
            raw['preview'] as Uint8List?,
            (raw['width'] as num).toDouble() /
                (raw['height'] as num).toDouble(),
            i + 1,
            total,
            classification.predictedLabel,
          ),
        );
      }
      await writer.writeString(
        '${jsonEncode({'type': 'completion', 'status': cancelled ? 'cancelled' : 'complete'})}\n',
      );
      return output;
    } catch (e, stack) {
      debugPrint('KSL_VIDEO_ERROR stage=$stage exception=$e stack=$stack');
      if (e is PlatformException) rethrow;
      throw StateError('Failed to $stage: $e');
    } finally {
      try {
        await writer?.close();
      } finally {
        try {
          await channel.invokeMethod<void>('closeVideo');
        } catch (e, stack) {
          debugPrint('KSL_VIDEO_ERROR closeVideo $e $stack');
        }
      }
    }
  }
}

class VideoAnalysisUpdate {
  const VideoAnalysisUpdate(
    this.frame,
    this.preview,
    this.aspectRatio,
    this.completed,
    this.total,
    this.label,
  );
  final TrackingFrame frame;
  final Uint8List? preview;
  final double aspectRatio;
  final int completed;
  final int total;
  final String label;
}
