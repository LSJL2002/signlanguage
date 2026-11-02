import 'dart:math' as math;

/// Selects MediaPipe Pose 33 into preprocess.txt's BODY_25 target order.
///
/// Targets: nose, neck, right shoulder/elbow/wrist, left shoulder/elbow/wrist,
/// mid-hip, right hip, left hip. Neck and mid-hip are derived approximations,
/// not independently detected BODY_25 joints. Coordinates remain in the input
/// space; no mirroring, scaling, confidence filtering or feature packing occurs.
class PoseTargetMapper {
  static List<Map<String, double>> map(List<Map<String, double>> pose) {
    if (pose.isEmpty) return [];
    if (pose.length != 33) {
      throw ArgumentError.value(
        pose.length,
        'pose.length',
        'Expected 33 points',
      );
    }
    Map<String, double> copy(int index) => Map.of(pose[index]);
    Map<String, double> midpoint(int a, int b) {
      final result = <String, double>{};
      for (final axis in ['x', 'y', 'z']) {
        final first = pose[a][axis], second = pose[b][axis];
        if (first != null && second != null) {
          result[axis] = (first + second) / 2;
        }
      }
      // A derived point is no more reliable than its less reliable endpoint.
      // These remain MediaPipe scores, not BODY_25 confidence values.
      for (final score in ['visibility', 'presence']) {
        final first = pose[a][score], second = pose[b][score];
        if (first != null && second != null) {
          result[score] = math.min(first, second);
        }
      }
      return result;
    }

    return [
      copy(0), // BODY_25 0: nose.
      midpoint(11, 12), // BODY_25 1: neck (derived).
      copy(12), // BODY_25 2: right shoulder.
      copy(14), // BODY_25 3: right elbow.
      copy(16), // BODY_25 4: right wrist.
      copy(11), // BODY_25 5: left shoulder.
      copy(13), // BODY_25 6: left elbow.
      copy(15), // BODY_25 7: left wrist.
      midpoint(23, 24), // BODY_25 8: mid-hip (derived).
      copy(24), // BODY_25 9: right hip.
      copy(23), // BODY_25 12: left hip.
    ];
  }
}
