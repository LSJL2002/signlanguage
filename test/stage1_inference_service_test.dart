import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/pose_service.dart';
import 'package:signlanguage/services/stage1_inference_service.dart';

List<List<Landmark?>> syntheticSequence(int count) => List.generate(
  count,
  (t) => List<Landmark?>.generate(123, (p) {
    if (p == 1) return {'x': 0.5, 'y': 0.4};
    if (p == 2) return {'x': 0.3, 'y': 0.4};
    if (p == 5) return {'x': 0.7, 'y': 0.4};
    return {'x': 0.4 + (p % 10) * 0.01 + t * 0.001, 'y': 0.5 + (p % 7) * 0.01};
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads actual float32 Stage 1 asset and validates tensor contract',
    () async {
      final service = await Stage1InferenceService.load();
      service.close();
      service.close();
      expect(
        () => service.inferLandmarks(syntheticSequence(1)),
        throwsStateError,
      );
    },
  );

  test('float32 T=1 produces finite logits', () async {
    final service = await Stage1InferenceService.load();
    addTearDown(service.close);
    final result = service.inferLandmarks(syntheticSequence(1));
    expect(result.inputShape, [1, 492, 1]);
    expect(result.outputShape, [1, 1, 2358]);
    expect(result.logits.single.single, hasLength(2358));
    expect(
      result.logits.single.single.every((value) => value.isFinite),
      isTrue,
    );
  });

  test('actual float32 inference resizes T=1 → 4 → 1 with finite raw logits', () async {
    final service = await Stage1InferenceService.load();
    addTearDown(service.close);
    for (final t in [1, 4, 1]) {
      final result = service.inferLandmarks(syntheticSequence(t));
      expect(result.inputShape, [1, 492, t]);
      expect(result.outputShape, [1, t, 2358]);
      expect(result.logits, hasLength(1));
      expect(result.logits.single, hasLength(t));
      for (final frame in result.logits.single) {
        expect(frame, hasLength(2358));
        expect(frame.every((value) => value.isFinite), isTrue);
      }
      // ignore: avoid_print
      print(
        'Stage 1 input=${result.inputShape} output=${result.outputShape} finite=true',
      );
    }
  });
}
