import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart'; // Import the gal package

import 'widgets/adaptive_translation_text.dart';
import 'history.dart';
import 'visual_style.dart';

List<CameraDescription> cameras = [];
const mockRecognizedText = '아이스 아메리카노 한 잔 주세요.';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error initializing camera: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Retained independently of Gallery for the future recognition pipeline.
  XFile? _capturedMedia;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lanying',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppPalette.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.accent,
          surface: AppPalette.paper,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppPalette.ink,
          elevation: 0,
          centerTitle: true,
        ),
        iconTheme: const IconThemeData(color: AppPalette.accent),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.accent,
            backgroundColor: const Color(0xB3FFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
      ),
      home: Builder(
        builder: (context) {
          if (cameras.isEmpty) {
            return Scaffold(
              appBar: AppBar(actions: const [HistoryButton()]),
              body: const Center(
                child: Text('No cameras found on this device'),
              ),
            );
          }
          return CameraScreen(
            cameras: cameras,
            onMediaCaptured: (file, isVideo) {
              _capturedMedia = file;
              if (!isVideo) {
                debugPrint(
                  '[photo] onMediaCaptured received: ${_capturedMedia!.path}',
                );
              }
            },
            onVideoSaved: () {
              ScaffoldMessenger.of(context).removeCurrentSnackBar();
              // Simulated recognition until model output is connected.
              const recognizedText = mockRecognizedText;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const CommunicationPage(recognizedText: recognizedText),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CommunicationPage extends StatefulWidget {
  const CommunicationPage({
    super.key,
    required this.recognizedText,
    this.history,
  });
  final String recognizedText;
  final RecognitionHistory? history;

  @override
  State<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends State<CommunicationPage> {
  RecognitionHistory get _history => widget.history ?? recognitionHistory;

  @override
  void initState() {
    super.initState();
    _history.add(widget.recognizedText);
  }

  @override
  void didUpdateWidget(covariant CommunicationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recognizedText != widget.recognizedText) {
      _history.add(widget.recognizedText);
    }
  }

  void _openCamera(BuildContext context) {
    Navigator.of(context).pop();
  }

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      HistoryButton(history: _history),
                      _CircleButton(
                        label: '打开相机',
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: AppPalette.accent,
                        ),
                        onPressed: () => _openCamera(context),
                      ),
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 340;
                        return Column(
                          children: [
                            const Spacer(flex: 5),
                            const Text(
                              '인식 결과',
                              style: TextStyle(
                                color: AppPalette.muted,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              flex: 4,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 660,
                                ),
                                child: AdaptiveTranslationText(
                                  text: widget.recognizedText,
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
                                color: AppPalette.ink,
                              ),
                            ),
                            const Spacer(flex: 3),
                          ],
                        );
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openCamera(context),
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 하기 / Try Again'),
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
  Widget build(BuildContext context) => const SoftBackground();
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
            color: Color(0x1552788C),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xCFFFFFFF),
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

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  final VoidCallback? onVideoSaved;

  /// Photos are delivered immediately; video delivery follows Gallery save.
  final void Function(XFile file, bool isVideo)? onMediaCaptured;

  const CameraScreen({
    super.key,
    required this.cameras,
    this.onVideoSaved,
    this.onMediaCaptured,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras[0], ResolutionPreset.high);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _recording = false;
  bool _busy = false;

  bool _held = false;

  bool get _ready => _controller.value.isInitialized;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Capture/save failed: $error')));
  }

  void _publish(XFile file, bool isVideo) {
    if (!mounted) return;
    widget.onMediaCaptured?.call(file, isVideo);
    widget.onVideoSaved
        ?.call(); // Existing result navigation for either media type.
  }

  Future<void> _takePhoto() async {
    debugPrint(
      '[photo] onTap: ready=$_ready busy=$_busy recording=$_recording platformRecording=${_controller.value.isRecordingVideo}',
    );
    if (_busy || _recording || _controller.value.isRecordingVideo) {
      debugPrint('[photo] blocked: capture or recording in progress');
      return;
    }
    if (!_ready) {
      _showError('Camera is not ready');
      return;
    }
    setState(() => _busy = true);
    try {
      debugPrint('[photo] calling takePicture');
      final photo = await _controller.takePicture();
      debugPrint('[photo] captured: ${photo.path}');
      // Diagnostics and Gallery are secondary, even if they are slow or fail.
      unawaited(_checkPhotoFile(photo));
      unawaited(_savePhotoToGallery(photo));
      _publish(photo, false);
    } catch (error) {
      debugPrint('[photo] failed: $error');
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPhotoFile(XFile photo) async {
    try {
      final bytes = await photo.length();
      debugPrint(
        '[photo] file exists/readable: true, bytes=$bytes, path=${photo.path}',
      );
    } catch (error) {
      debugPrint('[photo] file missing/unreadable: ${photo.path}; $error');
    }
  }

  Future<void> _savePhotoToGallery(XFile photo) async {
    try {
      await Gal.putImage(photo.path);
      debugPrint('[photo] Gallery save success: ${photo.path}');
    } catch (error) {
      debugPrint(
        '[photo] Gallery save failure (captured file retained): ${photo.path}; $error',
      );
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || _controller.value.isRecordingVideo) return;
    if (!_ready) {
      _showError('Camera is not ready');
      return;
    }
    _held = true;
    setState(() => _busy = true);
    try {
      await _controller.startVideoRecording();
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (error) {
      _held = false;
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Release can arrive before the platform finishes starting the recording.
    if (mounted && !_held && _recording) await _stopRecording();
  }

  void _releaseRecording() {
    _held = false;
    if (mounted) setState(() => _pressed = false);
    if (_recording && !_busy) _stopRecording();
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      final video = await _controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      await Gal.putVideo(video.path);
      _publish(video, true);
    } catch (error) {
      if (mounted) {
        setState(() => _recording = _controller.value.isRecordingVideo);
      }
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final stripHeight = MediaQuery.sizeOf(context).height * 0.075;
    const textShadow = [
      Shadow(color: Color(0x99000000), blurRadius: 5, offset: Offset(0, 1)),
    ];
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Camera unavailable'));
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final portrait =
                    MediaQuery.orientationOf(context) == Orientation.portrait;
                final ratio = portrait
                    ? 1 / _controller.value.aspectRatio
                    : _controller.value.aspectRatio;
                return ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 1000 * ratio,
                      height: 1000,
                      child: CameraPreview(_controller),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            bottom: stripHeight + 132,
            child: SafeArea(
              child: IgnorePointer(
                child: CustomPaint(painter: _ViewfinderGuides()),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    const Text(
                      'SIGN LANGUAGE',
                      style: TextStyle(
                        color: Color(0xFF6A818C),
                        fontSize: 12,
                        letterSpacing: 2.5,
                        shadows: textShadow,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xE6FFFFFF),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 12,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: IgnorePointer(
                        ignoring: _recording || _busy,
                        child: IconButton(
                          tooltip: '기록 / History',
                          icon: const Icon(
                            Icons.history,
                            color: Color(0xFF46565D),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  HistoryPage(history: recognitionHistory),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: stripHeight + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _busy
                        ? '처리 중…'
                        : _recording
                        ? '녹화 중'
                        : '수어를 들려주세요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      shadows: textShadow,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Translate: Please show sign language',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    shadows: textShadow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _busy
                      ? '저장 후 데모 결과를 표시합니다'
                      : _recording
                      ? '손을 떼면 녹화가 종료됩니다'
                      : '탭하여 촬영 · 길게 눌러 녹화',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: textShadow,
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  enabled: !_busy,
                  label: _recording
                      ? 'Release to stop recording'
                      : 'Take photo or hold to record',
                  child: AnimatedScale(
                    scale: _pressed ? 0.94 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF46565D),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: GestureDetector(
                          key: const Key('recordButton'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => setState(() => _pressed = true),
                          onTapUp: (_) => setState(() => _pressed = false),
                          onTapCancel: () => setState(() => _pressed = false),
                          onTap: _takePhoto,
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _releaseRecording(),
                          onLongPressCancel: _releaseRecording,
                          child: Center(
                            child: _busy
                                ? const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      key: Key('recordLoading'),
                                      strokeWidth: 2,
                                      color: Color(0xFF46565D),
                                    ),
                                  )
                                : Container(
                                    key: const Key('recordShape'),
                                    width: _recording ? 32 : 66,
                                    height: _recording ? 32 : 66,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEE7B6E),
                                      borderRadius: BorderRadius.circular(
                                        _recording ? 8 : 40,
                                      ),
                                      border: Border.all(
                                        color: const Color(0xFFBA625B),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: stripHeight,
            child: const ColoredBox(
              color: Color(0xFFF4F6F3),
              child: SafeArea(
                top: false,
                child: Center(
                  child: Text(
                    '데모 인식 · 실제 영상 저장',
                    style: TextStyle(color: Color(0xFF46565D), fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderGuides extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCF4F6F3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const inset = 16.0;
    const length = 18.0;
    for (final x in [inset, size.width - inset]) {
      for (final y in [inset, size.height - inset]) {
        final dx = x == inset ? length : -length;
        final dy = y == inset ? length : -length;
        canvas.drawPath(
          Path()
            ..moveTo(x + dx, y)
            ..lineTo(x, y)
            ..lineTo(x, y + dy),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ViewfinderGuides oldDelegate) => false;
}
