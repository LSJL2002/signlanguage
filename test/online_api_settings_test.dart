import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/online_api_settings_page.dart';
import 'package:signlanguage/services/online_api_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const defaults = OnlineApiSettings(
    serverUrl: 'https://default.example',
    apiKey: 'test-default',
  );
  const store = OnlineApiSettingsStore(defaults: defaults);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('unset settings use configured defaults', () async {
    final value = await store.load();
    expect(value.serverUrl, defaults.serverUrl);
    expect(value.apiKey, defaults.apiKey);
  });

  test(
    'saved settings survive a fresh store and blank key stays optional',
    () async {
      await store.save(
        const OnlineApiSettings(
          serverUrl: ' https://saved.example ',
          apiKey: '',
        ),
      );
      final value = await const OnlineApiSettingsStore(defaults: defaults)
          .load();
      expect(value.serverUrl, 'https://saved.example');
      expect(value.apiKey, isEmpty);
    },
  );

  test('malformed storage does not expose its contents', () async {
    FlutterSecureStorage.setMockInitialValues({
      OnlineApiSettingsStore.storageKey: 'private-value',
    });
    await expectLater(
      store.load(),
      throwsA(
        isA<StateError>().having(
          (e) => e.toString(),
          'message',
          isNot(contains('private-value')),
        ),
      ),
    );
  });

  testWidgets('settings mask the key and save edited values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnlineApiSettingsPage(store: store),
                ),
              ),
              child: const Text('Settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final keyField = find.descendant(
      of: find.byKey(const Key('onlineApiKey')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(keyField).obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('onlineServerUrl')),
      'https://saved.example',
    );
    await tester.enterText(
      find.byKey(const Key('onlineApiKey')),
      'test-edited',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Online API Settings'), findsNothing);
    final saved = await store.load();
    expect(saved.serverUrl, 'https://saved.example');
    expect(saved.apiKey, 'test-edited');
  });

  testWidgets('invalid URL cannot be saved', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnlineApiSettingsPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('onlineServerUrl')),
      'not a URL',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an HTTPS'), findsOneWidget);
    expect((await store.load()).serverUrl, defaults.serverUrl);
  });
}
