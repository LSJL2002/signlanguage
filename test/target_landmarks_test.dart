import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/face_target_mapper.dart';
import 'package:signlanguage/services/pose_service.dart';

// Independent expected order from the supplied target contract.
const expectedFaceIndices = [
  162,
  234,
  93,
  58,
  172,
  136,
  149,
  148,
  152,
  377,
  378,
  365,
  397,
  288,
  323,
  454,
  389,
  71,
  63,
  105,
  66,
  107,
  336,
  296,
  334,
  293,
  301,
  168,
  6,
  197,
  195,
  5,
  4,
  1,
  19,
  94,
  33,
  160,
  158,
  133,
  153,
  144,
  362,
  385,
  387,
  263,
  373,
  380,
  61,
  39,
  37,
  0,
  267,
  269,
  291,
  405,
  314,
  17,
  84,
  181,
  78,
  82,
  13,
  312,
  308,
  317,
  14,
  87,
  468,
  473,
];
List<Landmark> points(int length, double offset) => List.generate(
  length,
  (i) => {'x': offset + i, 'y': offset + i + .25, 'z': -offset - i},
);

void main() {
  test(
    'face mapping preserves every supplied position including iris points',
    () {
      final raw = points(478, 1000);
      final mapped = FaceTargetMapper.map(raw);
      expect(mapped, hasLength(70));
      for (var i = 0; i < 70; i++) {
        expect(
          mapped[i],
          raw[expectedFaceIndices[i]],
          reason: 'Face target $i',
        );
      }
      mapped[0]['x'] = -999;
      expect(raw[162]['x'], 1162);
    },
  );

  test(
    'combined frame retains Pose, Face, right then left order and metadata',
    () {
      final pose = points(33, 0);
      final face = points(478, 1000);
      final right = points(21, 2000);
      final left = points(21, 3000);
      final frame = TrackingFrame(
        frameId: 42,
        timestampUs: 123456,
        body: pose,
        face: face,
        rightHand: TrackedHand('Right', .9, right),
        leftHand: TrackedHand('Left', .8, left),
      );
      final mapped = frame.targetLandmarks123;
      expect(mapped, hasLength(123));
      expect(mapped.take(11), frame.targetPose11);
      for (var i = 0; i < 70; i++) {
        expect(mapped[11 + i], face[expectedFaceIndices[i]]);
      }
      expect(mapped.sublist(81, 102), right);
      expect(mapped.sublist(102, 123), left);
      expect(frame.frameId, 42);
      expect(frame.timestampUs, 123456);
      mapped[81]!['x'] = -999;
      expect(right[0]['x'], 2000);
      expect(frame.face.length, 478);
      expect(frame.body.length, 33);
    },
  );

  test(
    'missing groups keep fixed offsets instead of shifting or inventing data',
    () {
      final left = points(21, 3000);
      final frame = TrackingFrame(
        frameId: 1,
        timestampUs: 0,
        body: [],
        leftHand: TrackedHand('Left', .9, left),
      );
      expect(frame.targetFace70, isEmpty);
      expect(frame.targetLandmarks123, hasLength(123));
      expect(frame.targetLandmarks123.take(102), everyElement(isNull));
      expect(frame.targetLandmarks123.sublist(102), left);
      final right = points(21, 2000);
      final rightOnly = TrackingFrame(
        frameId: 2,
        timestampUs: 1,
        body: [],
        rightHand: TrackedHand('Right', .9, right),
      );
      expect(rightOnly.targetLandmarks123.sublist(81, 102), right);
      expect(rightOnly.targetLandmarks123.sublist(102), everyElement(isNull));
    },
  );

  test('incomplete nonempty face or hand groups are rejected', () {
    expect(() => FaceTargetMapper.map(points(468, 0)), throwsArgumentError);
    final invalid = TrackingFrame(
      frameId: 1,
      timestampUs: 0,
      body: [],
      rightHand: TrackedHand('Right', .9, points(20, 0)),
    );
    expect(() => invalid.targetLandmarks123, throwsArgumentError);
  });
}
