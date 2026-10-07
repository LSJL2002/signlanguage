import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/services/hand_detector_service.dart';
import 'package:signlanguage/services/pose_service.dart';
import 'package:signlanguage/services/video_analysis_service.dart';
import 'package:signlanguage/widgets/pose_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-analysis-test');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(PoseService.channel, null);
    await directory.delete(recursive: true);
  });
  HandAnalysisDebugResult classify(List<Landmark>? points) =>
      HandAnalysisDebugResult(
        hasHand: points != null,
        predictedSign: points == null ? -1 : 1,
        predictedLabel: points == null ? 'none' : 'test',
        logs: [],
      );
  Map<String, dynamic> packet(MethodCall call) => {
    ...Map<String, dynamic>.from(call.arguments as Map),
    'body': List.generate(
      33,
      (_) => {'x': .2, 'y': .3, 'z': .0, 'visibility': .9, 'presence': .9},
    ),
    'leftHand': {
      'handedness': 'Left',
      'confidence': .95,
      'landmarks': List.generate(21, (_) => {'x': .1, 'y': .4, 'z': .0}),
    },
    'face': List.generate(478, (_) => {'x': .2, 'y': .3, 'z': 0.0}),
    'rightHand': null,
    'width': 320,
    'height': 640,
  };
  test('sequential 10 FPS sampling retains complete raw landmarks and classifications', () async {
    final timestamps = <int>[];
    var closed = false;
    messenger.setMockMethodCallHandler(PoseService.channel, (call) async {
      switch (call.method) {
        case 'openVideo':
          return {'durationUs': 250001};
        case 'detectVideoFrame':
          timestamps.add(call.arguments['timestampUs'] as int);
          return packet(call);
        case 'closeVideo':
          closed = true;
          return null;
      }
      return null;
    });
    final updates = <VideoAnalysisUpdate>[];
    final file = File('${directory.path}/frames.jsonl');
    await VideoAnalysisService(classify: classify)
        .analyze('content://test', file, updates.add);
    expect(timestamps, [0, 100000, 200000]);
    expect(updates.last.completed, updates.last.total);
    expect(closed, isTrue);
    final records = (await file.readAsLines()).map(jsonDecode).toList();
    expect(records.first['timestampKind'], 'requestedSampleTimeUs');
    expect(records[1]['body'], hasLength(33));
    expect(records[1]['face'], hasLength(478));
    expect(records[1]['leftHand']['landmarks'], hasLength(21));
    expect(records[1]['classifierHand'], 'Left');
    expect(records.last['status'], 'complete');
  });
  test('cancellation during inference discards in-flight result and closes decoder', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var calls = 0;
    var closed = false;
    messenger.setMockMethodCallHandler(PoseService.channel, (call) async {
      if (call.method == 'openVideo') return {'durationUs': 1000000};
      if (call.method == 'closeVideo') {
        closed = true;
        return null;
      }
      calls++;
      started.complete();
      await gate.future;
      return packet(call);
    });
    final service = VideoAnalysisService(classify: classify);
    final task = service.analyze(
      'content://test',
      File('${directory.path}/cancel.jsonl'),
      (_) => fail('Cancelled frame published'),
    );
    await started.future;
    service.cancelled = true;
    gate.complete();
    await task;
    expect(calls, 1);
    expect(closed, isTrue);
  });
  test('decoder failure closes resources and propagates failure', () async {
    var closed = false;
    messenger.setMockMethodCallHandler(PoseService.channel, (call) async {
      if (call.method == 'openVideo') return {'durationUs': 1000000};
      if (call.method == 'closeVideo') {
        closed = true;
        return null;
      }
      throw PlatformException(code: 'VIDEO_DECODE');
    });
    await expectLater(
      VideoAnalysisService(classify: classify).analyze(
        'content://broken',
        File('${directory.path}/failure.jsonl'),
        (_) {},
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(closed, isTrue);
  });
  test('pose connections retain arms but exclude head and fingers', () {
    expect(
      PosePainter.connections.expand((e) => e).any((i) => i < 11),
      isFalse,
    );
    expect(PosePainter.connections, contains(equals([13, 15])));
    expect(
      PosePainter.connections
          .expand((e) => e)
          .any(PosePainter.excludedHandPoints.contains),
      isFalse,
    );
    expect(VideoAnalysisService.sampleCount(100001), 2);
  });
}
