import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/history.dart';
import 'package:signlanguage/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const cameraChannel = MethodChannel('plugins.flutter.io/camera');
  const galleryChannel = MethodChannel('gal');
  var failCapture = false;
  var failSave = false;
  var creates = 0;
  var saves = 0;
  Completer<void>? saveGate;
  Completer<void>? startGate;
  var starts = 0;
  var stops = 0;
  var photos = 0;
  var denyCamera = false;

  setUp(() {
    failCapture = false;
    failSave = false;
    creates = 0;
    saves = 0;
    saveGate = null;
    startGate = null;
    starts = 0;
    stops = 0;
    photos = 0;
    denyCamera = false;
    cameras = [
      const CameraDescription(
        name: 'test-camera',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
    messenger.setMockMethodCallHandler(cameraChannel, (call) async {
      switch (call.method) {
        case 'create':
          if (denyCamera) throw PlatformException(code: 'CameraAccessDenied');
          creates++;
          return {'cameraId': 0};
        case 'initialize':
          await messenger.handlePlatformMessage(
            'flutter.io/cameraPlugin/camera0',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('initialized', {
                'previewWidth': 640.0,
                'previewHeight': 480.0,
                'exposureMode': 'auto',
                'exposurePointSupported': false,
                'focusMode': 'auto',
                'focusPointSupported': false,
              }),
            ),
            (_) {},
          );
          return null;
        case 'takePicture':
          photos++;
          if (failCapture) throw PlatformException(code: 'capture_failed');
          return '/tmp/test-capture.jpg';
        case 'startVideoRecording':
          starts++;
          await startGate?.future;
          if (failCapture) throw PlatformException(code: 'capture_failed');
          return null;
        case 'stopVideoRecording':
          stops++;
          if (failCapture) throw PlatformException(code: 'capture_failed');
          return '/tmp/test-capture.mp4';
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(galleryChannel, (call) async {
      if (call.method == 'requestAccess' || call.method == 'hasAccess') {
        return true;
      }
      if (call.method == 'putVideo' || call.method == 'putImage') {
        expect(
          (call.arguments as Map)['path'],
          call.method == 'putVideo'
              ? '/tmp/test-capture.mp4'
              : '/tmp/test-capture.jpg',
        );
        if (failSave) throw PlatformException(code: 'accessDenied');
        await saveGate?.future;
        saves++;
      }
      return null;
    });
  });

  tearDown(() {
    cameras = [];
    messenger.setMockMethodCallHandler(cameraChannel, null);
    messenger.setMockMethodCallHandler(galleryChannel, null);
  });

  testWidgets('missing cameras shows a message without creating a result', (
    tester,
  ) async {
    cameras = [];
    final before = recognitionHistory.records.length;
    await tester.pumpWidget(const MyApp());
    expect(find.text('No cameras found on this device'), findsOneWidget);
    expect(find.byType(CommunicationPage), findsNothing);
    expect(recognitionHistory.records.length, before);
  });

  testWidgets('capture, result, History and retry reuse the original camera', (
    tester,
  ) async {
    final before = recognitionHistory.records.length;
    final started = DateTime.now();
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.byType(CameraPreview), findsOneWidget);
    final cameraState = tester.state(find.byType(CameraScreen));
    for (var count = 1; count <= 2; count++) {
      await tester.tap(find.byKey(const Key('recordButton')));
      await tester.pumpAndSettle();
      expect(saves, count);
      expect(photos, count);
      expect(starts, 0);
      expect(find.bySemanticsLabel(mockRecognizedText), findsOneWidget);
      expect(recognitionHistory.records.length, before + count);
      expect(
        recognitionHistory.records.first.recognizedText,
        mockRecognizedText,
      );
      expect(
        recognitionHistory.records.first.timestamp.isBefore(started),
        isFalse,
      );
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(recognitionHistory.records.length, before + count);
      await tester.tap(find.byTooltip('기록 / History'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HistoryPage>(find.byType(HistoryPage)).history,
        same(recognitionHistory),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 하기 / Try Again'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CameraScreen)), same(cameraState));
      expect(
        Navigator.of(tester.element(find.byType(CameraScreen))).canPop(),
        isFalse,
      );
      expect(creates, 1);
      await tester.tap(find.byTooltip('기록 / History'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HistoryPage>(find.byType(HistoryPage)).history,
        same(recognitionHistory),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(recognitionHistory.records.length, before + count);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('centered control changes shape and locks while saving', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('recordButton'));
    expect(tester.getCenter(button).dx, 160);
    expect(tester.getSize(find.byKey(const Key('recordShape'))).width, 66);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Release to stop recording'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('recordShape'))).width, 32);
    saveGate = Completer<void>();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('recordLoading')), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(find.byType(CommunicationPage), findsNothing);
    saveGate!.complete();
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byType(CommunicationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('release during startup stops once and exposes saved paths', (
    tester,
  ) async {
    final captures = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CameraScreen(
          cameras: cameras,
          onMediaCaptured: (file, video) =>
              captures.add('${video ? 'video' : 'photo'}:${file.path}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('recordButton'));
    startGate = Completer<void>();
    final hold = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 600));
    await hold.up();
    await tester.pump();
    expect(starts, 1);
    expect(stops, 0);
    await tester.tap(button);
    expect(photos, 0);
    startGate!.complete();
    await tester.pumpAndSettle();
    expect(stops, 1);
    expect(captures, ['video:/tmp/test-capture.mp4']);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(captures, [
      'video:/tmp/test-capture.mp4',
      'photo:/tmp/test-capture.jpg',
    ]);
    expect(starts, 1);
  });

  testWidgets('active recording rejects photo and second start', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('recordButton'));
    final hold = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    // Exercise the callback guards without ending the original hold gesture.
    final control = tester.widget<GestureDetector>(button);
    control.onTap!();
    control.onLongPressStart!(const LongPressStartDetails());
    await tester.pump();
    expect(photos, 0);
    expect(starts, 1);
    await hold.up();
    await tester.pumpAndSettle();
    expect(stops, 1);
    expect(saves, 1);
  });

  testWidgets('camera permission failure safely rejects capture', (
    tester,
  ) async {
    denyCamera = true;
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Camera unavailable'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();
    expect(photos, 0);
    expect(starts, 0);
    expect(find.textContaining('Camera is not ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'photo path and result are delivered before Gallery completes or fails',
    (tester) async {
      saveGate = Completer<void>();
      final before = recognitionHistory.records.length;
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recordButton')));
      await tester.pumpAndSettle();
      expect(photos, 1);
      expect(saves, 0);
      expect(find.byType(CommunicationPage), findsOneWidget);
      expect(recognitionHistory.records.length, before + 1);
      saveGate!.completeError(PlatformException(code: 'accessDenied'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunicationPage), findsOneWidget);
      expect(recognitionHistory.records.length, before + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Gallery failure retains original XFile through callback', (
    tester,
  ) async {
    failSave = true;
    XFile? received;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraScreen(
          cameras: cameras,
          onMediaCaptured: (file, video) {
            expect(video, isFalse);
            received = file;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();
    expect(received, isNotNull);
    expect(received!.path, '/tmp/test-capture.jpg');
    expect(photos, 1);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['capture']) {
    testWidgets('$failure failure does not navigate or record a result', (
      tester,
    ) async {
      failCapture = failure == 'capture';
      failSave = failure == 'save';
      final before = recognitionHistory.records.length;
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recordButton')));
      await tester.pumpAndSettle();
      expect(find.byType(CameraScreen), findsOneWidget);
      expect(find.byType(CommunicationPage), findsNothing);
      expect(find.textContaining('Capture/save failed:'), findsOneWidget);
      expect(recognitionHistory.records.length, before);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('result and Try Again remain visible on a small screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final history = RecognitionHistory();
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CommunicationPage(recognizedText: '테스트 결과', history: history),
      ),
    );
    expect(find.bySemanticsLabel('테스트 결과'), findsOneWidget);
    expect(find.text('다시 하기 / Try Again').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
