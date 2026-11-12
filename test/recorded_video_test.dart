import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:signlanguage/services/video_prediction_api.dart';

import 'package:flutter/material.dart';
// Camera's platform interface is used only for the recording test double.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/src/method_channel/method_channel_camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:signlanguage/widgets/translation_mode_pill.dart';
import 'package:signlanguage/widgets/debug_overlay.dart';
import 'package:signlanguage/widgets/pose_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/camera');
  var starts = 0;
  var stops = 0;
  var photos = 0;
  Completer<void>? startGate;
  String videoPath = '/missing/recording.mp4';
  const camera = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  setUp(() {
    CameraPlatform.instance = _StreamingCamera();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera/imageStream'),
      (_) async => null,
    );
    starts = stops = photos = 0;
    startGate = null;
    videoPath = '/missing/recording.mp4';
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'create':
          return {'cameraId': 0};
        case 'initialize':
          unawaited(
            messenger.handlePlatformMessage(
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
            ),
          );
          return null;
        case 'startVideoRecording':
          starts++;
          await startGate?.future;
          return null;
        case 'stopVideoRecording':
          stops++;
          return videoPath;
        case 'takePicture':
          photos++;
          return '/missing/photo.jpg';
        default:
          return null;
      }
    });
  });
  tearDown(() {
    CameraPlatform.instance = MethodChannelCamera();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera/imageStream'),
      null,
    );
  });

  Future<void> open(WidgetTester tester, {VideoPredictionApi? api}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CameraScreen(cameras: const [camera], predictionApi: api),
      ),
    );
    // Initialization uses platform callbacks; avoid waiting on periodic tracking.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'tap starts video without photo; second tap stops and missing file has no result',
    (tester) async {
      await open(tester);
      final button = find.byKey(const Key('recordButton'));
      await tester.tap(button);
      await tester.pump();
      expect(starts, 1);
      expect(photos, 0);
      expect(tester.getSize(find.byKey(const Key('recordShape'))).width, 32);
      await tester.tap(button);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(stops, 1);
      expect(find.byType(CommunicationPage), findsNothing);
      expect(find.textContaining('Capture/save failed'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'pending start ignores duplicate taps and release does not stop recording',
    (tester) async {
      await open(tester);
      startGate = Completer<void>();
      final button = find.byKey(const Key('recordButton'));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(starts, 1);
      expect(stops, 0);
      expect(photos, 0);
      startGate!.complete();
      await tester.pump();
      expect(stops, 0);
      await close(tester);
    },
  );
  for (final source in ['recording', 'upload']) {
    for (final online in [false, true]) {
      for (final failServer in online ? [false, true] : [false]) {
        testWidgets(
          '$source with online=$online routes to selected backend, serverFailure=$failServer',
          (tester) async {
            late Directory dir;
            await tester.runAsync(() async {
              dir = await Directory.systemTemp.createTemp(
                'recorded-video-test',
              );
              videoPath = '${dir.path}/video.mp4';
              await File(videoPath).writeAsBytes([1, 2, 3]);
            });
            final previousPicker = FilePickerPlatform.instance;
            FilePickerPlatform.instance = _VideoPicker(videoPath);
            addTearDown(() => FilePickerPlatform.instance = previousPicker);
            const picker = MethodChannel(
              'com.example.signlanguage/video_picker',
            );
            messenger.setMockMethodCallHandler(picker, (_) async => videoPath);
            const pose = MethodChannel('com.example.signlanguage/pose');
            const paths = MethodChannel('plugins.flutter.io/path_provider');
            const stage1 = MethodChannel(
              'com.example.signlanguage/stage1_onnx',
            );
            const stage2 = MethodChannel(
              'com.example.signlanguage/stage2_onnx',
            );
            var localCalls = 0;
            messenger.setMockMethodCallHandler(paths, (_) async => dir.path);
            messenger.setMockMethodCallHandler(pose, (call) async {
              if (call.method == 'initialize') return true;
              if (call.method == 'openVideo') {
                expect(call.arguments['uri'], videoPath);
                return {'durationUs': 100000};
              }
              if (call.method == 'detectVideoFrame') {
                return {
                  'frameId': 0,
                  'timestampUs': 0,
                  'body': [],
                  'face': [],
                  'width': 640,
                  'height': 480,
                };
              }
              return null;
            });
            messenger.setMockMethodCallHandler(stage1, (call) async {
              localCalls++;
              final classes = call.arguments['classes'] as int;
              final logits = ByteData(classes * 4)
                ..setFloat32(4, 20, Endian.little);
              return {
                'shape': [1, 1, classes],
                'logits': logits.buffer.asUint8List(),
              };
            });
            messenger.setMockMethodCallHandler(
              stage2,
              (_) async => '번역 결과입니다.',
            );
            addTearDown(() {
              for (final channel in [picker, pose, paths, stage1, stage2]) {
                messenger.setMockMethodCallHandler(channel, null);
              }
            });
            final api = _Prediction()..fail = failServer;
            await open(tester, api: api);
            await tester.runAsync(() async {
              if (online) {
                await tester.tap(find.byType(TranslationModePill));
                await tester.pump();
              }
              if (source == 'recording') {
                final button = find.byKey(const Key('recordButton'));
                await tester.tap(button);
                await tester.pump();
                await tester.tap(button);
              } else {
                await tester.tap(find.text('Upload'));
              }
              for (
                var i = 0;
                i < 60 && find.byType(CommunicationPage).evaluate().isEmpty;
                i++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                await tester.pump(const Duration(milliseconds: 30));
              }
            });
            expect(api.calls, online ? 1 : 0);
            expect(localCalls, online ? 0 : 1);
            if (online) expect(api.bytes, [1, 2, 3]);
            if (failServer) {
              expect(find.byType(CommunicationPage), findsNothing);
              expect(find.text('Server unavailable for test'), findsOneWidget);
            } else {
              expect(
                tester
                    .widget<CommunicationPage>(find.byType(CommunicationPage))
                    .recognizedText,
                '번역 결과입니다.',
              );
            }
            expect(photos, 0);
            await close(tester);
            await tester.runAsync(() => dir.delete(recursive: true));
          },
        );
      }
    }
  }

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(412, 915),
    const Size(800, 360),
  ]) {
    testWidgets('Camera layout and visual mode toggle at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final api = _Prediction();
      await open(tester, api: api);
      final button = find.byKey(const Key('recordButton'));
      final pill = find.byType(TranslationModePill);
      final label = find.byKey(const Key('recordLabel'));
      expect(tester.getCenter(button).dx, closeTo(size.width / 2, .1));
      expect(tester.getCenter(label).dx, closeTo(size.width / 2, .1));
      expect(
        tester.getRect(label).top,
        greaterThan(tester.getRect(button).bottom),
      );
      expect(
        tester.getRect(pill).left,
        greaterThan(tester.getRect(button).right),
      );
      expect(tester.getRect(pill).right, lessThanOrEqualTo(size.width - 16));
      expect(
        tester.getCenter(pill).dy,
        closeTo(tester.getCenter(button).dy, .1),
      );
      expect(find.text('수어를 보여주세요'), findsOneWidget);
      expect(find.text('녹화'), findsOneWidget);
      expect(find.text('KEYPOINT CLASSIFIER'), findsNothing);
      expect(find.textContaining('Pointing / Close / Open'), findsNothing);
      expect(find.byType(DebugOverlay), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is TrackingPainter,
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_ViewfinderGuides',
        ),
        findsOneWidget,
      );
      expect(find.text('Upload'), findsOneWidget);
      expect(find.byTooltip('기록 / History'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(pill);
      await tester.pump();
      expect(find.text('Online'), findsOneWidget);
      expect(tester.widget<TranslationModePill>(pill).isOnlineMode, isTrue);
      await tester.tap(pill);
      await tester.pump();
      expect(find.text('Offline'), findsOneWidget);
      expect(api.calls, 0);
      expect(starts, 0);
      expect(photos, 0);
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets('backgrounding cancels a pending recording without prediction', (
    tester,
  ) async {
    final api = _Prediction();
    await open(tester, api: api);
    startGate = Completer<void>();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    startGate!.complete();
    await tester.pump();
    expect(stops, 1);
    expect(api.calls, 0);
    await close(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

class _Prediction implements VideoPredictionApi {
  bool fail = false;
  int calls = 0;
  List<int> bytes = [];
  @override
  Future<PredictionResult> predict(
    Stream<List<int>> videoBytes, {
    required int size,
    required void Function(int sent, int total) onProgress,
  }) async {
    calls++;
    await for (final chunk in videoBytes) {
      bytes.addAll(chunk);
    }
    if (fail) {
      throw const VideoPredictionException('Server unavailable for test');
    }
    onProgress(bytes.length, size);
    return const PredictionResult(glosses: 'test', sentence: '번역 결과입니다.');
  }
}

class _StreamingCamera extends MethodChannelCamera {
  @override
  bool supportsImageStreaming() => true;
}

class _VideoPicker extends FilePickerPlatform {
  _VideoPicker(this.path);
  final String path;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _VideoFile(path);
}

final class _VideoFile extends PlatformFile {
  _VideoFile(String path) : xFile = XFile(path);
  @override
  final XFile xFile;
  @override
  String get name => xFile.name;
  @override
  Uri get uri => Uri.file(xFile.path);
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() => xFile.length();
  @override
  Future<Uint8List> readAsBytes() => xFile.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() =>
      xFile.openRead().map(Uint8List.fromList);
}
