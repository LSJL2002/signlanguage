import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Result of Korean sentence -> glosses -> keypoint motion.
///
/// [pose] is flat `[frames, 123, 4]`: per point `[x, y, dx, dy]`, centred on
/// the shoulders (shoulders at x = ±0.5, y grows downwards).
/// Point layout: 0–10 body, 11–80 face (70-point), 81–101 hand A, 102–122 hand B.
class TextToSignResult {
  TextToSignResult({
    required this.glosses,
    required this.durations,
    required this.pose,
    required this.frames,
  }) : _glossStarts = _starts(durations);

  static const joints = 123;
  static const channels = 4;
  static const fps = 30;

  final List<String> glosses;
  final List<int> durations;
  final Float32List pose;
  final int frames;
  final List<int> _glossStarts;

  Duration get length => Duration(milliseconds: (frames * 1000 / fps).round());

  double x(int frame, int joint) => pose[(frame * joints + joint) * channels];
  double y(int frame, int joint) => pose[(frame * joints + joint) * channels + 1];

  /// Index into [glosses] of the sign being shown at [frame].
  int glossIndexAt(int frame) {
    for (var i = _glossStarts.length - 1; i >= 0; i--) {
      if (frame >= _glossStarts[i]) return i;
    }
    return 0;
  }

  static List<int> _starts(List<int> durations) {
    final starts = <int>[];
    var total = 0;
    for (final d in durations) {
      starts.add(total);
      total += d;
    }
    return starts;
  }
}

/// Runs the text-to-sign ONNX models in TextToSignChannel.kt (Android).
class TextToSignService {
  static const channel = MethodChannel('com.example.signlanguage/text_to_sign');

  /// [speed] > 1 makes every sign last longer; < 1 makes signing faster.
  Future<TextToSignResult> generate(String sentence, {double speed = 1.0}) async {
    final text = sentence.trim();
    if (text.isEmpty) throw StateError('Please enter a sentence.');
    final Map<String, dynamic>? map;
    try {
      map = await channel.invokeMapMethod<String, dynamic>('generate', {
        'sentence': text,
        'speed': speed,
      });
    } on MissingPluginException {
      throw StateError('Text to sign is only available on Android.');
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Text to sign failed.');
    }
    if (map == null) throw StateError('Text to sign returned no result.');

    final glosses = (map['glosses'] as List).cast<String>();
    final durations = List<int>.from(map['durations'] as Iterable);
    final pose = map['pose'] as Float32List;
    final frames = map['frames'] as int;
    if (pose.length != frames * TextToSignResult.joints * TextToSignResult.channels) {
      throw StateError('Unexpected pose size: ${pose.length} for $frames frames.');
    }
    return TextToSignResult(
      glosses: glosses,
      durations: durations,
      pose: pose,
      frames: frames,
    );
  }
}
