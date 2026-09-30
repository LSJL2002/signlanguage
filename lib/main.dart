import 'package:flutter/material.dart';

import 'widgets/adaptive_translation_text.dart';

const mockRecognizedText = '아이스 아메리카노 한 잔 주세요.';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lanying',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      ),
      home: const CommunicationPage(recognizedText: mockRecognizedText),
    );
  }
}

class CommunicationPage extends StatelessWidget {
  const CommunicationPage({super.key, required this.recognizedText});
  final String recognizedText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CommunicationBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _CircleButton(
                      label: '설정',
                      child: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () {},
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 340;
                        return Column(
                          children: [
                            const Spacer(flex: 5),
                            Expanded(
                              flex: 4,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 660,
                                ),
                                child: AdaptiveTranslationText(
                                  text: recognizedText,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 16 : 44),
                            _CircleButton(
                              label: '번역 문장 듣기',
                              light: true,
                              size: compact ? 64 : 104,
                              onPressed: () {},
                              child: Icon(
                                Icons.volume_up_rounded,
                                size: compact ? 32 : 48,
                                color: const Color(0xFF20262B),
                              ),
                            ),
                            const Spacer(flex: 3),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunicationBackground extends StatelessWidget {
  const _CommunicationBackground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFAEBBC8), Color(0xFFE5E3DC), Color(0xFFA7B5C6)],
      ),
    ),
    child: Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.8, -0.7),
              radius: 0.85,
              colors: [Color(0xA6EAD6B3), Color(0x00EAD6B3)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.9, 0.35),
              radius: 0.95,
              colors: [Color(0x99F3E5DA), Color(0x00F3E5DA)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.65, 0.65),
              radius: 0.7,
              colors: [Color(0x99EFDDD7), Color(0x00EFDDD7)],
            ),
          ),
        ),
      ],
    ),
  );
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.label,
    required this.child,
    required this.onPressed,
    this.size = 48,
    this.light = false,
  });
  final String label;
  final Widget child;
  final VoidCallback onPressed;
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: light ? const Color(0xD9FFFFFF) : const Color(0x55232A31),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(child: child),
        ),
      ),
    ),
  );
}
