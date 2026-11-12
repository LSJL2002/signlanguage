import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const defaultApiBaseUrl =
    'https://interactive-anderson-scope-lang.trycloudflare.com';
const maxVideoBytes = 90 * 1024 * 1024;
const _requestTimeout = Duration(minutes: 10);

const configuredApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: defaultApiBaseUrl,
);
const configuredApiToken = String.fromEnvironment('API_TOKEN');

class PredictionResult {
  const PredictionResult({required this.glosses, required this.sentence});

  final String glosses;
  final String sentence;
}

class VideoPredictionException implements Exception {
  const VideoPredictionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class VideoPredictionApi {
  Future<PredictionResult> predict(
    Stream<List<int>> videoBytes, {
    required int size,
    required void Function(int sent, int total) onProgress,
  });
}

class VideoPredictionClient implements VideoPredictionApi {
  VideoPredictionClient({
    required this.baseUrl,
    required this.apiToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiToken;
  final http.Client _client;

  @override
  Future<PredictionResult> predict(
    Stream<List<int>> videoBytes, {
    required int size,
    required void Function(int sent, int total) onProgress,
  }) async {
    if (size > maxVideoBytes) {
      throw const VideoPredictionException(
        'This video is larger than the 90 MiB upload limit. Choose a smaller video.',
      );
    }
    if (apiToken.trim().isEmpty) {
      throw const VideoPredictionException(
        'The API token is not configured. Add it to your local config/dev.json file.',
      );
    }

    late final Uri endpoint;
    try {
      endpoint = Uri.parse(
        '${baseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/predict',
      );
      if (!endpoint.hasScheme || endpoint.host.isEmpty) {
        throw const FormatException();
      }
    } on FormatException {
      throw const VideoPredictionException(
        'The API address is invalid. Check the configured base URL.',
      );
    }

    final request = http.StreamedRequest('POST', endpoint)
      ..contentLength = size
      ..headers.addAll({
        HttpHeaders.authorizationHeader: 'Bearer ${apiToken.trim()}',
        HttpHeaders.contentTypeHeader: 'application/octet-stream',
      });

    var sent = 0;
    final response = await _sendAndRead(request, videoBytes, (chunkSize) {
      sent += chunkSize;
      onProgress(sent, size);
    });

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorForStatus(response.statusCode);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['glosses'] is! String ||
          decoded['sentence'] is! String) {
        throw const FormatException();
      }
      return PredictionResult(
        glosses: decoded['glosses'] as String,
        sentence: decoded['sentence'] as String,
      );
    } on FormatException {
      throw const VideoPredictionException(
        'The prediction could not be read. Please try again.',
      );
    }
  }

  Future<({int statusCode, String body})> _sendAndRead(
    http.StreamedRequest request,
    Stream<List<int>> videoBytes,
    void Function(int chunkSize) onChunkSent,
  ) async {
    try {
      return await (() async {
        final responseFuture = _client.send(request);
        await request.sink.addStream(
          videoBytes.map((chunk) {
            onChunkSent(chunk.length);
            return chunk;
          }),
        );
        await request.sink.close();
        final response = await responseFuture;
        return (
          statusCode: response.statusCode,
          body: await response.stream.bytesToString(),
        );
      })().timeout(_requestTimeout);
    } on TimeoutException {
      throw const VideoPredictionException(
        'The upload or prediction took too long. Check your connection and try again.',
      );
    } on SocketException {
      throw const VideoPredictionException(
        'Could not connect to the prediction service. Check your internet connection and try again.',
      );
    } on HandshakeException {
      throw const VideoPredictionException(
        'A secure connection could not be established. Check your internet connection and try again.',
      );
    } on http.ClientException {
      throw const VideoPredictionException(
        'Could not connect to the prediction service. Check your internet connection and try again.',
      );
    } on FileSystemException {
      throw const VideoPredictionException(
        'The selected video could not be read. Choose it again and try once more.',
      );
    } on PlatformException {
      throw const VideoPredictionException(
        'The selected video could not be read. Choose it again and try once more.',
      );
    }
  }

  VideoPredictionException _errorForStatus(int statusCode) {
    return switch (statusCode) {
      401 || 403 => const VideoPredictionException(
        'The API did not authorize this request. Check the configured API token.',
      ),
      413 => const VideoPredictionException(
        'This video is larger than the 90 MiB upload limit. Choose a smaller video.',
      ),
      415 || 422 => const VideoPredictionException(
        'This video format or content is not supported. Choose another video.',
      ),
      404 => const VideoPredictionException(
        'The prediction service could not be found. Check the configured API address.',
      ),
      >= 500 => const VideoPredictionException(
        'The prediction service is having a problem. Please try again later.',
      ),
      _ => const VideoPredictionException(
        'The video could not be processed. Choose another video and try again.',
      ),
    };
  }

  void close() => _client.close();
}
