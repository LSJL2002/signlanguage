import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/pose_service.dart';
import 'package:signlanguage/services/pose_target_mapper.dart';

void main() {
  List<Landmark> pose() => List.generate(
    33,
    (i) => {
      'x': i / 100,
      'y': i / 50,
      'z': -i / 100,
      'visibility': i / 40,
      'presence': 1 - i / 40,
    },
  );

  test(
    'target order matches BODY_25 selection, including derived torso joints',
    () {
      final source = pose();
      final frame = TrackingFrame(frameId: 1, timestampUs: 10, body: source);
      final target = frame.targetPose11;
      expect(target, hasLength(11));
      // Expected target semantics, not BODY_25 indices applied to MediaPipe.
      const sources = {
        0: 0,
        2: 12,
        3: 14,
        4: 16,
        5: 11,
        6: 13,
        7: 15,
        9: 24,
        10: 23,
      };
      for (final entry in sources.entries) {
        expect(target[entry.key], source[entry.value]);
      }
      expect(target[1]['x'], closeTo(.115, 1e-12));
      expect(target[1]['y'], closeTo(.23, 1e-12));
      expect(target[1]['z'], closeTo(-.115, 1e-12));
      expect(target[8]['x'], closeTo(.235, 1e-12));
      expect(target[8]['y'], closeTo(.47, 1e-12));
      expect(target[8]['z'], closeTo(-.235, 1e-12));
      expect(target[1]['visibility'], source[11]['visibility']);
      expect(target[1]['presence'], source[12]['presence']);
      target[0]['x'] = 99;
      expect(source[0]['x'], 0);
      expect(frame.body, hasLength(33));
    },
  );

  test(
    'absent and malformed detections do not manufacture valid target poses',
    () {
      expect(PoseTargetMapper.map([]), isEmpty);
      expect(() => PoseTargetMapper.map([{}]), throwsArgumentError);
      final source = pose();
      source[11].remove('x');
      source[23]['y'] = double.nan;
      final target = PoseTargetMapper.map(source);
      expect(target[1].containsKey('x'), isFalse);
      expect(target[8]['y']!.isNaN, isTrue);
    },
  );
}
