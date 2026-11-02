import 'dart:math' as math;

import 'pose_service.dart';

/// Sequence-only port of preprocess.txt for mapped MediaPipe (3D-source) data.
/// Missing slots become NaN, not valid zero coordinates. The reference leaves
/// never-observed points unrepaired, so output may contain NaN. This does not
/// invoke a model or alter the existing realtime/classifier pipeline.
class SequencePreprocessor {
  static const pointCount = 123;
  static const neckIndex = 1;
  static const rightShoulderIndex = 2;
  static const leftShoulderIndex = 5;
  static const epsilon = 1e-6;
  static const interpolationLimit = 10;
  static const maxJump = 1.0;

  /// Returns [T][123][4], each point [x, y, dx, dy], in input frame order.
  /// Velocity is a frame difference, not divided by elapsed time.
  static List<List<List<double>>> fromTrackingFrames(
    List<TrackingFrame> frames,
  ) => preprocess([for (final frame in frames) frame.targetLandmarks123]);

  static List<List<List<double>>> preprocess(List<List<Landmark?>> frames) {
    for (final frame in frames) {
      if (frame.length != pointCount) {
        throw ArgumentError.value(
          frame.length,
          'frame.length',
          'Expected 123 slots',
        );
      }
    }
    if (frames.isEmpty) return [];
    final xy = [
      for (final frame in frames)
        [
          for (final p in frame) [p?['x'] ?? double.nan, p?['y'] ?? double.nan],
        ],
    ];
    // MediaPipe z is depth, not the 2D dataset's confidence channel.
    final valid = [
      for (final frame in xy)
        [for (final p in frame) p[0].isFinite && p[1].isFinite],
    ];
    _repair(xy, valid);
    // The Python repair function copies its mask. Normalization deliberately
    // receives the original validity mask, matching process_keypoints exactly.
    final widths = _shoulderWidths(xy);
    final goodWidths = <double>[
      for (var t = 0; t < xy.length; t++)
        if (valid[t][rightShoulderIndex] &&
            valid[t][leftShoulderIndex] &&
            widths[t].isFinite &&
            widths[t] > epsilon)
          widths[t],
    ];
    final medianWidth = goodWidths.isEmpty ? 1.0 : _median(goodWidths);
    final validNecks = [
      for (var t = 0; t < xy.length; t++)
        if (valid[t][neckIndex]) t,
    ];
    // Snapshot origins before normalizing any frame (nearest may point backward).
    final necks = [for (final frame in xy) List<double>.of(frame[neckIndex])];
    for (var t = 0; t < xy.length; t++) {
      var origin = <double>[0, 0];
      if (validNecks.isNotEmpty) {
        var nearest = validNecks.first;
        for (final candidate in validNecks) {
          if ((candidate - t).abs() < (nearest - t).abs()) nearest = candidate;
        }
        origin = necks[nearest];
      }
      final scale = goodWidths.isEmpty
          ? 1.0
          : (widths[t].isFinite && widths[t] > epsilon
                ? widths[t]
                : medianWidth);
      for (final point in xy[t]) {
        point[0] = (point[0] - origin[0]) / (scale + epsilon);
        point[1] = (point[1] - origin[1]) / (scale + epsilon);
      }
    }
    return [
      for (var t = 0; t < xy.length; t++)
        [
          for (var p = 0; p < pointCount; p++)
            [
              xy[t][p][0],
              xy[t][p][1],
              t == 0 ? 0.0 : xy[t][p][0] - xy[t - 1][p][0],
              t == 0 ? 0.0 : xy[t][p][1] - xy[t - 1][p][1],
            ],
        ],
    ];
  }

  static double _distance(List<double> a, List<double> b) =>
      math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));

  static List<double> _shoulderWidths(List<List<List<double>>> xy) => [
    for (final frame in xy)
      _distance(frame[rightShoulderIndex], frame[leftShoulderIndex]),
  ];

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static void _repair(
    List<List<List<double>>> xy,
    List<List<bool>> originalValid,
  ) {
    final valid = [for (final row in originalValid) List<bool>.of(row)];
    final widths = _shoulderWidths(xy)
        .where((v) => v.isFinite && v > epsilon)
        .toList();
    final threshold = (widths.isEmpty ? 1.0 : _median(widths)) * maxJump;
    for (var t = 1; t < xy.length; t++) {
      for (var p = 0; p < pointCount; p++) {
        final distance = _distance(xy[t][p], xy[t - 1][p]);
        valid[t][p] =
            valid[t][p] &&
            (!valid[t - 1][p] || (distance.isFinite && distance <= threshold));
      }
    }
    for (var p = 0; p < pointCount; p++) {
      final good = [
        for (var t = 0; t < xy.length; t++)
          if (valid[t][p]) t,
      ];
      if (good.isEmpty) continue;
      var nextIndex = 0;
      for (var t = 0; t < xy.length; t++) {
        while (nextIndex < good.length && good[nextIndex] < t) {
          nextIndex++;
        }
        if (valid[t][p]) continue;
        final previous = nextIndex > 0 ? good[nextIndex - 1] : null;
        final next = nextIndex < good.length ? good[nextIndex] : null;
        for (var axis = 0; axis < 2; axis++) {
          if (previous == null) {
            xy[t][p][axis] = xy[next!][p][axis];
          } else if (next != null && next - previous <= interpolationLimit) {
            final ratio = (t - previous) / (next - previous);
            xy[t][p][axis] =
                xy[previous][p][axis] * (1 - ratio) + xy[next][p][axis] * ratio;
          } else {
            xy[t][p][axis] = xy[previous][p][axis];
          }
        }
      }
    }
  }
}
