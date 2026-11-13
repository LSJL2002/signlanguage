import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'video_prediction_api.dart';

class OnlineApiSettings {
  const OnlineApiSettings({required this.serverUrl, required this.apiKey});
  final String serverUrl;
  final String apiKey;

  static String? validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'Enter an HTTPS server URL without credentials, query, or fragment.';
    }
    return null;
  }
}

class OnlineApiSettingsStore {
  const OnlineApiSettingsStore({
    this.storage = const FlutterSecureStorage(),
    this.defaults = const OnlineApiSettings(
      serverUrl: configuredApiBaseUrl,
      apiKey: configuredApiToken,
    ),
  });
  final FlutterSecureStorage storage;
  final OnlineApiSettings defaults;
  static const storageKey = 'signflow.online_api_settings';

  Future<OnlineApiSettings> load() async {
    try {
      final value = await storage.read(key: storageKey);
      if (value == null) return defaults;
      final data = jsonDecode(value) as Map<String, dynamic>;
      return OnlineApiSettings(
        serverUrl: data['serverUrl'] as String,
        apiKey: data['apiKey'] as String,
      );
    } catch (_) {
      // Never propagate storage/JSON errors that could contain credentials.
      throw StateError('Unable to read saved Online API settings.');
    }
  }

  Future<void> save(OnlineApiSettings settings) async {
    final error = OnlineApiSettings.validateUrl(settings.serverUrl);
    if (error != null) throw ArgumentError(error);
    try {
      await storage.write(
        key: storageKey,
        value: jsonEncode({
          'serverUrl': settings.serverUrl.trim(),
          'apiKey': settings.apiKey.trim(),
        }),
      );
    } catch (_) {
      throw StateError('Unable to save Online API settings.');
    }
  }
}
