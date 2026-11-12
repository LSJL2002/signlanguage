import 'package:flutter/material.dart';

import '../services/api_settings.dart';

class ApiSettingsDialog extends StatefulWidget {
  const ApiSettingsDialog({super.key, required this.settings});

  final ApiSettings settings;

  @override
  State<ApiSettingsDialog> createState() => _ApiSettingsDialogState();
}

class _ApiSettingsDialogState extends State<ApiSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiTokenController;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.settings.baseUrl);
    _apiTokenController = TextEditingController(text: widget.settings.apiToken);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ApiSettings(
        baseUrl: _baseUrlController.text.trim().replaceFirst(
          RegExp(r'/+$'),
          '',
        ),
        apiToken: _apiTokenController.text.trim(),
      ),
    );
  }

  String? _validateBaseUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return 'Enter a valid HTTP or HTTPS API base URL.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('API settings'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('apiBaseUrlField'),
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'API base URL',
                hintText: 'https://example.com',
              ),
              keyboardType: TextInputType.url,
              validator: _validateBaseUrl,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('apiTokenField'),
              controller: _apiTokenController,
              decoration: InputDecoration(
                labelText: 'API token',
                suffixIcon: IconButton(
                  tooltip: _showToken ? 'Hide token' : 'Show token',
                  onPressed: () => setState(() => _showToken = !_showToken),
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              obscureText: !_showToken,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an API token.'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your token is saved securely on this device.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
