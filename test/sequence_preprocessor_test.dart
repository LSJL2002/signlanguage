import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/pose_service.dart';
import 'package:signlanguage/services/sequence_preprocessor.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/sequence_preprocess_reference.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('matches preprocess.txt: ${c['name']}', () {
      final frames = List.generate(c['frames'] as int, (t) {
        final frame = List<Landmark?>.generate(
          123,
          (_) => {'x': 1, 'y': 2, 'z': -9},
        );
        frame[1] = {'x': 2, 'y': 0};
        frame[2] = {'x': 0, 'y': 0};
        frame[5] = {'x': 4, 'y': 0};
        final transform = c['transforms']?[t] as List?;
        if (transform != null) {
          for (final p in frame) {
            p!['x'] =
                p['x']! * (transform[0] as num).toDouble() +
                (transform[1] as num).toDouble();
            p['y'] =
                p['y']! * (transform[0] as num).toDouble() +
                (transform[2] as num).toDouble();
          }
        }
        return frame;
      });
      for (final o in c['overrides'] as List) {
        final v = o['value'] as Map?;
        frames[o['frame'] as int][o['point'] as int] = v?.map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        );
      }
      final before = jsonEncode(frames);
      final result = SequencePreprocessor.preprocess(frames);
      expect(result, hasLength(frames.length));
      for (var t = 0; t < result.length; t++) {
        expect(result[t], hasLength(123));
        for (final p in result[t]) {
          expect(p, hasLength(4));
          if (t == 0) expect(p.sublist(2), [0.0, 0.0]);
        }
        for (var i = 0; i < (c['indices'] as List).length; i++) {
          final point = c['indices'][i] as int;
          for (var axis = 0; axis < 4; axis++) {
            final expected = c['expected'][t][i][axis] as num?;
            expect(
              result[t][point][axis],
              expected == null ? isNaN : closeTo(expected.toDouble(), 1e-5),
              reason: 'frame=$t point=$point feature=$axis',
            );
          }
        }
      }
      expect(
        jsonEncode(frames),
        before,
        reason: 'must not mutate source frames',
      );
    });
  }
  test('empty sequence and malformed frame length', () {
    expect(SequencePreprocessor.preprocess([]), isEmpty);
    expect(() => SequencePreprocessor.preprocess([[]]), throwsArgumentError);
  });
  test(
    'tracking adapter preserves missing slots and produces first velocity zero',
    () {
      final result = SequencePreprocessor.fromTrackingFrames([
        const TrackingFrame(frameId: 1, timestampUs: 123, body: []),
      ]);
      expect(result.single, hasLength(123));
      for (final p in result.single) {
        expect(p[0], isNaN);
        expect(p[1], isNaN);
        expect(p.sublist(2), [0.0, 0.0]);
      }
    },
  );
}
