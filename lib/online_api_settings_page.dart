import 'package:flutter/material.dart';

import 'services/online_api_settings.dart';

class OnlineApiSettingsPage extends StatefulWidget {
  const OnlineApiSettingsPage({
    super.key,
    this.store = const OnlineApiSettingsStore(),
  });
  final OnlineApiSettingsStore store;
  @override
  State<OnlineApiSettingsPage> createState() => _OnlineApiSettingsPageState();
}

class _OnlineApiSettingsPageState extends State<OnlineApiSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.store.load();
      if (!mounted) return;
      _url.text = settings.serverUrl;
      _key.text = settings.apiKey;
    } catch (_) {
      _error = 'Unable to load settings. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(
        OnlineApiSettings(serverUrl: _url.text, apiKey: _key.text),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to save settings. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Online API Settings')),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    key: const Key('onlineServerUrl'),
                    controller: _url,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://your-server',
                    ),
                    validator: (value) =>
                        OnlineApiSettings.validateUrl(value ?? ''),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('onlineApiKey'),
                    controller: _key,
                    enabled: !_saving,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: const InputDecoration(
                      labelText: 'API key (optional)',
                      helperText: 'Leave empty to send without an API key.',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
    ),
  );
}
