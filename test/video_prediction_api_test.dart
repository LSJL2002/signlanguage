import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signlanguage/services/video_prediction_api.dart';

void main() {
  late Directory tempDirectory;
  late File video;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('prediction-test');
    video = File('${tempDirectory.path}${Platform.pathSeparator}sample.mp4');
    await video.writeAsBytes([0, 1, 2, 255]);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'sends video bytes as the raw request body and parses the result',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://example.com/api/predict');
        expect(request.headers['authorization'], 'Bearer local-test-token');
        expect(request.headers['content-type'], 'application/octet-stream');
        expect(request.bodyBytes, [0, 1, 2, 255]);
        return http.Response(
          '{"glosses":"HELLO","sentence":"안녕하세요."}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = VideoPredictionClient(
        baseUrl: 'https://example.com/api/',
        apiToken: 'local-test-token',
        client: client,
      );

      final result = await api.predict(
        video.openRead(),
        size: 4,
        onProgress: (sent, total) {},
      );

      expect(result.glosses, 'HELLO');
      expect(result.sentence, '안녕하세요.');
      api.close();
    },
  );

  test('rejects a video over 90 MiB without making a request', () async {
    var sentRequest = false;
    final client = MockClient((request) async {
      sentRequest = true;
      return http.Response('{}', 200);
    });
    final api = VideoPredictionClient(
      baseUrl: 'https://example.com',
      apiToken: 'token',
      client: client,
    );

    await expectLater(
      api.predict(
        video.openRead(),
        size: maxVideoBytes + 1,
        onProgress: (sent, total) {},
      ),
      throwsA(
        isA<VideoPredictionException>().having(
          (error) => error.message,
          'message',
          contains('90 MiB'),
        ),
      ),
    );
    expect(sentRequest, isFalse);
    api.close();
  });

  test(
    'converts auth, unsupported-video, and server failures to friendly text',
    () async {
      for (final (status, expected) in [
        (401, 'did not authorize'),
        (403, 'did not authorize'),
        (413, '90 MiB'),
        (415, 'not supported'),
        (422, 'not supported'),
        (500, 'having a problem'),
      ]) {
        final api = VideoPredictionClient(
          baseUrl: 'https://example.com',
          apiToken: 'token',
          client: MockClient(
            (request) async => http.Response('private logs', status),
          ),
        );

        await expectLater(
          api.predict(video.openRead(), size: 4, onProgress: (sent, total) {}),
          throwsA(
            isA<VideoPredictionException>()
                .having((error) => error.message, 'message', contains(expected))
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('private logs')),
                ),
          ),
        );
        api.close();
      }
    },
  );

  test('allows an optional API key without an Authorization header', () async {
    final api = VideoPredictionClient(
      baseUrl: 'https://example.com',
      apiToken: '',
      client: MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('{"glosses":"HELLO","sentence":"Hello"}', 200);
      }),
    );
    final result = await api.predict(
      video.openRead(),
      size: 4,
      onProgress: (sent, total) {},
    );
    expect(result.sentence, 'Hello');
    api.close();
  });

  test('turns network failures into a friendly message', () async {
    final api = VideoPredictionClient(
      baseUrl: 'https://example.com',
      apiToken: 'token',
      client: MockClient(
        (request) async => throw http.ClientException('private network detail'),
      ),
    );

    await expectLater(
      api.predict(video.openRead(), size: 4, onProgress: (sent, total) {}),
      throwsA(
        isA<VideoPredictionException>()
            .having(
              (error) => error.message,
              'message',
              contains('internet connection'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private network detail')),
            ),
      ),
    );
    api.close();
  });
}
