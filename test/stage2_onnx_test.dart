import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/stage2_onnx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(Stage2OnnxService.channel, null),
  );

  test('empty Stage 1 gloss never invokes Stage 2', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(Stage2OnnxService.channel, (_) async {
      calls++;
      return 'unexpected';
    });
    await expectLater(Stage2OnnxService().translate('  '), throwsStateError);
    expect(calls, 0);
  });
  test(
    'passes unchanged gloss and returns the generated Korean sentence',
    () async {
      messenger.setMockMethodCallHandler(Stage2OnnxService.channel, (
        call,
      ) async {
        expect(call.method, 'translate');
        expect(call.arguments['gloss'], '전국1 햇빛2');
        return '전국이 맑겠습니다.';
      });
      expect(await Stage2OnnxService().translate('전국1 햇빛2'), '전국이 맑겠습니다.');
    },
  );
  test(
    'empty model output and native errors are not fabricated translations',
    () async {
      messenger.setMockMethodCallHandler(
        Stage2OnnxService.channel,
        (_) async => '',
      );
      await expectLater(Stage2OnnxService().translate('전국1'), throwsStateError);
      messenger.setMockMethodCallHandler(
        Stage2OnnxService.channel,
        (_) async =>
            throw PlatformException(code: 'STAGE2_ONNX', message: 'failed'),
      );
      await expectLater(
        Stage2OnnxService().translate('전국1'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
