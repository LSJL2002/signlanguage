import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/stage1_onnx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'mapping and float32 features match Python including missing groups',
    () {
      final fixture = jsonDecode(
        File('test/fixtures/stage1_onnx_reference.json').readAsStringSync(),
      ) as Map;
      final frames = [
        for (final raw in fixture['raw'] as List)
          Stage1OnnxService.mapFrame(raw as Map),
      ];
      final bytes = Stage1OnnxService.pack(frames);
      final data = ByteData.sublistView(bytes);
      final expected = fixture['expected'] as List;
      expect(bytes.length, 3 * 492 * 4);
      for (var i = 0; i < expected.length; i++) {
        expect(
          data.getFloat32(i * 4, Endian.little),
          closeTo((expected[i] as num).toDouble(), 1e-6),
          reason: 'feature $i',
        );
      }
      expect(() => Stage1OnnxService.pack([]), throwsArgumentError);
    },
  );
  test('gloss collapse resets at blank and low-confidence boundaries', () {
    expect(
      Stage1OnnxService.decode(
        [
          [0, 10, 0, 0],
          [0, 10, 0, 0],
          [10, 0, 0, 0],
          [0, 10, 0, 0],
          [0, 0, 0, 0],
          [0, 10, 0, 0],
          [0, 0, 10, 0],
        ],
        {0: 'blank', 1: 'one', 2: 'two', 3: 'three'},
      ),
      'one one one two',
    );
  });
  test(
    'channel sends float32 [1,T,492] and decodes real vocabulary IDs',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final vocab = jsonDecode(
        await rootBundle.loadString('saved_models/gloss_to_id.json'),
      ) as Map;
      final word = vocab.entries.firstWhere((e) => e.value == 1).key;
      messenger.setMockMethodCallHandler(Stage1OnnxService.channel, (
        call,
      ) async {
        expect(call.method, 'infer');
        expect(call.arguments['frames'], 2);
        expect(call.arguments['classes'], vocab.length);
        expect((call.arguments['features'] as Uint8List).length, 2 * 492 * 4);
        final bytes = ByteData(2 * vocab.length * 4);
        for (var t = 0; t < 2; t++) {
          bytes.setFloat32((t * vocab.length + 1) * 4, 20, Endian.little);
        }
        return {
          'shape': [1, 2, vocab.length],
          'logits': bytes.buffer.asUint8List(),
        };
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(Stage1OnnxService.channel, null),
      );
      expect(
        await Stage1OnnxService().infer([
          Stage1OnnxService.mapFrame({}),
          Stage1OnnxService.mapFrame({}),
        ]),
        word,
      );
    },
  );
}
