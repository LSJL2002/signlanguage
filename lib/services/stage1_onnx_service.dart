import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Python-reference Stage 1 boundary, independent of the legacy preprocessing.
class Stage1OnnxService {
  static const channel = MethodChannel('com.example.signlanguage/stage1_onnx');
  static const faceIndices = [
    234,
    93,
    132,
    58,
    172,
    136,
    150,
    149,
    176,
    152,
    377,
    400,
    378,
    379,
    365,
    397,
    288,
    70,
    63,
    105,
    66,
    107,
    336,
    296,
    334,
    293,
    300,
    168,
    6,
    197,
    195,
    5,
    4,
    1,
    19,
    94,
    468,
    469,
    470,
    471,
    472,
    133,
    473,
    474,
    475,
    476,
    477,
    362,
    61,
    185,
    40,
    39,
    37,
    0,
    267,
    269,
    270,
    409,
    291,
    375,
    321,
    405,
    314,
    17,
    84,
    181,
    91,
    146,
  ];

  /// Direct model order: Pose 11, Face 70, RIGHT 21, LEFT 21.
  /// Python saves LEFT/RIGHT but swaps them before its 492-feature inference.
  /// Use the raw packet so overlay confidence filtering does not discard hands.
  static List<List<double>> mapFrame(Map raw) {
    final mirrored = raw['mirror'] == true;
    List<List<double>> group(dynamic value, int count) {
      final list = (value as List?) ?? [];
      if (list.isEmpty) return List.generate(count, (_) => [0.0, 0.0]);
      if (list.length != count) {
        throw ArgumentError('Expected $count landmarks');
      }
      return [
        for (final p in list)
          [
            mirrored
                ? 1 - (p['x'] as num).toDouble()
                : (p['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
          ],
      ];
    }

    List<double> midpoint(List<double> a, List<double> b) => [
      (a[0] + b[0]) / 2,
      (a[1] + b[1]) / 2,
    ];
    final pose = group(raw['body'], 33);
    final face = group(raw['face'], 478);
    return [
      pose[0],
      midpoint(pose[11], pose[12]),
      pose[12],
      pose[14],
      pose[16],
      pose[11],
      pose[13],
      pose[15],
      midpoint(pose[23], pose[24]),
      pose[24],
      pose[23],
      for (final index in faceIndices) face[index],
      midpoint(face[33], face[133]),
      midpoint(face[362], face[263]),
      ...group(raw['rightHand']?['landmarks'], 21),
      ...group(raw['leftHand']?['landmarks'], 21),
    ];
  }

  /// Packed little-endian float32 [1,T,492], landmark-major [x,y,dx,dy].
  /// Reference uses zero-filled missing points, no repair, and no extra epsilon.
  static Uint8List pack(List<List<List<double>>> frames) {
    if (frames.isEmpty || frames.length > 3000) {
      throw ArgumentError(
        'Stage 1 requires 1–3000 frames; no silent truncation',
      );
    }
    final packed = ByteData(frames.length * 492 * 4);
    Float32List? previous;
    // Match NumPy float32 rounding at intermediate normalization operations.
    final scratch = Float32List(1);
    double f32(double value) {
      scratch[0] = value;
      return scratch[0];
    }

    for (var t = 0; t < frames.length; t++) {
      final frame = frames[t];
      if (frame.length != 123 ||
          frame.any((p) => p.length != 2 || p.any((v) => !v.isFinite))) {
        throw ArgumentError('Expected 123 finite xy points');
      }
      final xy = Float32List.fromList([for (final p in frame) ...p]);
      final cx = f32(f32(xy[4] + xy[10]) / 2);
      final cy = f32(f32(xy[5] + xy[11]) / 2);
      final sx = f32(xy[4] - xy[10]), sy = f32(xy[5] - xy[11]);
      final width = f32(math.sqrt(f32(f32(sx * sx) + f32(sy * sy))));
      final scale = width > 1e-6 ? width : 1.0;
      final normalized = Float32List(246);
      for (var p = 0; p < 123; p++) {
        final x = f32(f32(xy[p * 2] - cx) / scale);
        final y = f32(f32(xy[p * 2 + 1] - cy) / scale);
        normalized[p * 2] = x;
        normalized[p * 2 + 1] = y;
        final features = [
          x,
          y,
          previous == null ? 0.0 : f32(x - previous[p * 2]),
          previous == null ? 0.0 : f32(y - previous[p * 2 + 1]),
        ];
        for (var f = 0; f < 4; f++) {
          if (!features[f].isFinite) {
            throw StateError('Non-finite Stage 1 input');
          }
          packed.setFloat32(
            ((t * 123 + p) * 4 + f) * 4,
            features[f],
            Endian.little,
          );
        }
      }
      previous = normalized;
    }
    return packed.buffer.asUint8List();
  }

  static String decode(List<List<double>> logits, Map<int, String> vocab) {
    var previous = -1;
    final words = <String>[];
    final counts = <int, int>{};
    var blank = 0;
    var nonBlankPass = 0;
    var nonBlankBelow = 0;
    var confidenceMin = 1.0;
    var confidenceMax = 0.0;
    var confidenceSum = 0.0;
    for (final row in logits) {
      if (row.isEmpty || row.any((x) => !x.isFinite)) {
        throw StateError('Invalid logits');
      }
      var best = 0;
      for (var i = 1; i < row.length; i++) {
        if (row[i] > row[best]) best = i;
      }
      final denominator = row.fold<double>(
        0,
        (sum, x) => sum + math.exp(x - row[best]),
      );
      final confidence = 1 / denominator;
      counts.update(best, (n) => n + 1, ifAbsent: () => 1);
      confidenceMin = math.min(confidenceMin, confidence);
      confidenceMax = math.max(confidenceMax, confidence);
      confidenceSum += confidence;
      if (best == 0) {
        blank++;
      } else if (confidence < .3) {
        nonBlankBelow++;
      } else {
        nonBlankPass++;
      }
      if (best == 0 || 1 / denominator < .3) {
        previous = 0;
        continue;
      }
      if (best != previous) {
        final word = vocab[best] ?? '';
        if (word.isNotEmpty) words.add(word);
        previous = best;
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final frequency = b.value.compareTo(a.value);
        return frequency != 0 ? frequency : a.key.compareTo(b.key);
      });
    debugPrint(
      'KSL_STAGE1_STATS ${jsonEncode({
        'frames': logits.length,
        'blank': blank,
        'nonBlankBelowThreshold': nonBlankBelow,
        'nonBlankPassThreshold': nonBlankPass,
        'maxSoftmaxConfidence': {'min': logits.isEmpty ? null : confidenceMin, 'mean': logits.isEmpty ? null : confidenceSum / logits.length, 'max': logits.isEmpty ? null : confidenceMax},
        'top5': ranked.take(5).map((e) => {'id': e.key, 'gloss': vocab[e.key], 'frames': e.value}).toList(),
      })}',
    );
    return words.join(' ');
  }

  Future<String> infer(List<List<List<double>>> frames) async {
    final vocabulary = jsonDecode(
      await rootBundle.loadString('saved_models/gloss_to_id.json'),
    ) as Map;
    final ids = <int, String>{
      for (final e in vocabulary.entries)
        (e.value as num).toInt(): e.key as String,
    };
    if (ids.length != vocabulary.length ||
        !ids.containsKey(0) ||
        ids.keys.any((i) => i < 0 || i >= ids.length)) {
      throw StateError('Invalid gloss vocabulary');
    }
    final result = await channel.invokeMapMethod<String, dynamic>('infer', {
      'features': pack(frames),
      'frames': frames.length,
      'classes': ids.length,
    });
    final shape = (result?['shape'] as List?)?.cast<int>();
    if (shape == null ||
        shape.length != 3 ||
        shape[0] != 1 ||
        shape[1] != frames.length ||
        shape[2] != ids.length) {
      throw StateError('Unexpected ONNX output shape: $shape');
    }
    final bytes = result!['logits'] as Uint8List;
    if (bytes.length != frames.length * ids.length * 4) {
      throw StateError('Invalid logits size');
    }
    final data = ByteData.sublistView(bytes);
    return decode(
      List.generate(
        frames.length,
        (t) => List.generate(
          ids.length,
          (c) => data.getFloat32((t * ids.length + c) * 4, Endian.little),
        ),
      ),
      ids,
    );
  }
}
