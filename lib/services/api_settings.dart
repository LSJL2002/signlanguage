import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'video_prediction_api.dart';

class ApiSettings {
  const ApiSettings({required this.baseUrl, required this.apiToken});

  final String baseUrl;
  final String apiToken;
}

abstract interface class ApiSettingsStore {
  Future<ApiSettings> read();
  Future<void> write(ApiSettings settings);
}

class SecureApiSettingsStore implements ApiSettingsStore {
  const SecureApiSettingsStore({this._storage = const FlutterSecureStorage()});

  static const _key = 'api_settings';
  final FlutterSecureStorage _storage;

  @override
  Future<ApiSettings> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) {
      return const ApiSettings(
        baseUrl: configuredApiBaseUrl,
        apiToken: configuredApiToken,
      );
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['baseUrl'] is! String ||
        decoded['apiToken'] is! String) {
      throw const FormatException('Saved API settings are invalid.');
    }
    return ApiSettings(
      baseUrl: decoded['baseUrl'] as String,
      apiToken: decoded['apiToken'] as String,
    );
  }

  @override
  Future<void> write(ApiSettings settings) => _storage.write(
    key: _key,
    value: jsonEncode({
      'baseUrl': settings.baseUrl,
      'apiToken': settings.apiToken,
    }),
  );
}
