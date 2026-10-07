import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/pose_service.dart';
import 'package:signlanguage/widgets/pose_painter.dart';

CameraImage frame() {
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 35,
    'width': 4,
    'height': 4,
    'planes': [
      {'bytes': Uint8List(24), 'bytesPerRow': 6, 'bytesPerPixel': 1},
      {'bytes': Uint8List(8), 'bytesPerRow': 4, 'bytesPerPixel': 2},
      {'bytes': Uint8List(12), 'bytesPerRow': 6, 'bytesPerPixel': 2},
    ],
  });
}

Map<String, dynamic> hand(String side, double x, {double confidence = .9}) => {
  'handedness': side,
  'confidence': confidence,
  'landmarks': List.generate(21, (_) => {'x': x, 'y': .5, 'z': 0.0}),
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(PoseService.channel, null));

  test('missing native detector fails gracefully', () async {
    final service = PoseService();
    await service.initialize();
    expect(service.error, 'Body tracking unavailable');
    await service.close();
  });
  test('rotation covers both lenses and all orientations', () {
    const orientations = DeviceOrientation.values;
    for (final front in [false, true]) {
      for (final sensor in [90, 270]) {
        for (final orientation in orientations) {
          final degrees = switch (orientation) {
            DeviceOrientation.portraitUp => 0,
            DeviceOrientation.landscapeLeft => 90,
            DeviceOrientation.portraitDown => 180,
            DeviceOrientation.landscapeRight => 270,
          };
          expect(
            poseRotation(sensor, orientation, front),
            (sensor + (front ? degrees : -degrees) + 360) % 360,
          );
        }
      }
    }
  });
  test('frame associates body and anatomical hands, not screen order', () {
    final value = TrackingFrame.fromMap({
      'frameId': 7,
      'timestampUs': 123,
      'body': List.generate(
        33,
        (_) => {'x': .5, 'y': .5, 'z': 0.0, 'visibility': 1.0, 'presence': 1.0},
      ),
      'face': List.generate(478, (_) => {'x': .2, 'y': .3, 'z': 0.0}),
      'leftHand': hand('Left', .9),
      'rightHand': hand('Right', .1),
    });
    expect(value.body.length, 33);
    expect(value.face.length, 478);
    expect(value.leftHand!.side, 'Left');
    expect(value.leftHand!.landmarks.first['x'], .9);
    expect(value.rightHand!.landmarks.length, 21);
    expect(value.frameId, 7);
    expect(value.timestampUs, 123);
    expect(TrackedHand.parse(hand('Left', .5, confidence: .2), 'Left'), isNull);
    expect(TrackedHand.parse(hand('Right', .5), 'Left'), isNull);
  });
  test(
    'preserves strides and rejects old packets; absence clears every group',
    () async {
      var fail = false;
      var stale = false;
      Map<dynamic, dynamic>? arguments;
      messenger.setMockMethodCallHandler(PoseService.channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'detect') {
          arguments = call.arguments as Map;
          if (fail) throw PlatformException(code: 'POSE_ERROR');
          return {
            'frameId': stale ? 0 : arguments!['frameId'],
            'timestampUs': arguments!['timestampUs'],
            'body': [],
            'leftHand': null,
            'rightHand': null,
          };
        }
        return null;
      });
      final service = PoseService();
      await service.initialize();
      Future<TrackingFrame?> detect() => service.detect(
        frame(),
        rotation: 90,
        mirror: true,
        frameId: 1,
        timestampUs: 100,
      );
      final empty = (await detect())!;
      expect(empty.body, isEmpty);
      expect(empty.leftHand, isNull);
      expect(empty.rightHand, isNull);
      expect(arguments!['uStride'], 4);
      expect(arguments!['vStride'], 6);
      expect(arguments!['rotation'], 90);
      expect(arguments!['mirror'], true);
      stale = true;
      expect(await detect(), isNull);
      fail = true;
      expect(await detect(), isNull);
      expect(service.error, isNotNull);
      await service.close();
      expect(await detect(), isNull);
    },
  );
  test('does not queue inference and rejects completion after close', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    messenger.setMockMethodCallHandler(PoseService.channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'detect') {
        calls++;
        return pending.future;
      }
      return null;
    });
    final service = PoseService();
    await service.initialize();
    final first = service.detect(
      frame(),
      rotation: 0,
      mirror: false,
      frameId: 1,
      timestampUs: 1,
    );
    expect(
      await service.detect(
        frame(),
        rotation: 0,
        mirror: false,
        frameId: 2,
        timestampUs: 2,
      ),
      isNull,
    );
    await service.close();
    pending.complete({'frameId': 1, 'timestampUs': 1, 'body': []});
    expect(await first, isNull);
    expect(calls, 1);
  });
  test(
    'low-confidence body points not drawn and missing frame leaves no pixels',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      PosePainter([
        ...List.generate(11, (_) => <String, double>{}),
        {'x': .5, 'y': .5, 'visibility': 1, 'presence': 1},
        {'x': .1, 'y': .1, 'visibility': .1, 'presence': 1},
      ]).paint(canvas, const Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData())!;
      expect(bytes.getUint8((50 * 100 + 50) * 4 + 3), greaterThan(0));
      expect(bytes.getUint8((10 * 100 + 10) * 4 + 3), 0);
      image.dispose();
      picture.dispose();
    },
  );
  test(
    'overlay uses independent face and Hand wrist without Pose head or fingers',
    () async {
      final body = List<Landmark>.generate(
        33,
        (_) => {'x': 0, 'y': 0, 'visibility': 0, 'presence': 0},
      );
      body[0] = {'x': .1, 'y': .1, 'visibility': .4, 'presence': .4};
      body[15] = {'x': .3, 'y': .3, 'visibility': 1, 'presence': 1};
      body[17] = {'x': .8, 'y': .8, 'visibility': 1, 'presence': 1};
      final face = List<Landmark>.generate(
        478,
        (_) => {'x': .6, 'y': .2, 'z': 0},
      );
      face[338] = {'x': .8, 'y': .2, 'z': 0};
      final tracking = TrackingFrame(
        frameId: 1,
        timestampUs: 0,
        body: body,
        face: face,
        leftHand: TrackedHand(
          'Left',
          .9,
          List.generate(21, (_) => {'x': .5, 'y': .5, 'z': 0}),
        ),
      );
      final recorder = ui.PictureRecorder();
      TrackingPainter(tracking).paint(Canvas(recorder), const Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData())!;
      int alpha(int x, int y) => bytes.getUint8((y * 100 + x) * 4 + 3);
      expect(alpha(10, 10), 0);
      expect(alpha(70, 20), greaterThan(0));
      expect(alpha(50, 50), greaterThan(0));
      expect(alpha(30, 30), 0);
      expect(alpha(80, 80), 0);
      expect(tracking.body.length, 33);
      image.dispose();
      picture.dispose();
    },
  );
}
