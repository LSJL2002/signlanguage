import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';

import 'widgets/adaptive_translation_text.dart';
import 'history.dart';
import 'visual_style.dart';
import 'services/hand_detector_service.dart';
import 'widgets/debug_overlay.dart';
import 'services/pose_service.dart';
import 'widgets/pose_painter.dart';
import 'video_analysis_page.dart';

final trackingRouteObserver = RouteObserver<ModalRoute<void>>();
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
  String _lastRecognizedText = mockRecognizedText;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [trackingRouteObserver],
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
              if (!isVideo) {
                debugPrint('[photo] onMediaCaptured received: ${file.path}');
              }
            },
            onRecognitionResult: (recognizedText) {
              setState(() {
                _lastRecognizedText = recognizedText;
              });
            },
            onVideoSaved: () {
              ScaffoldMessenger.of(context).removeCurrentSnackBar();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CommunicationPage(recognizedText: _lastRecognizedText),
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
  final void Function(XFile file, bool isVideo)? onMediaCaptured;
  final void Function(String recognizedText)? onRecognitionResult;

  const CameraScreen({
    super.key,
    required this.cameras,
    this.onVideoSaved,
    this.onMediaCaptured,
    this.onRecognitionResult,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  final HandDetectorService _handDetectorService = HandDetectorService();

  final PoseService _poseService = PoseService();
  bool _debugFacePoints = false;
  TrackingFrame? _trackingFrame;
  DeviceOrientation? _trackingOrientation;
  final Stopwatch _trackingClock = Stopwatch()..start();
  int _lastTrackingUs = -100000;
  int _frameId = 0;
  int _epoch = 0;
  bool _visible = true;
  bool _foreground = true;
  Timer? _expiryTimer;
  ModalRoute<void>? _route;
  double _trackingFps = 0;
  int _lastCompletionUs = 0;
  Future<void> _lifecycle = Future.value();
  bool _isProcessingLiveFrame = false;
  bool _hasHand = false;
  List<Map<String, double>>? _currentLandmarks;
  int _predictedFingers = -1;
  String _predictedLabel = '';
  List<HandDebugLog> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CameraController(widget.cameras[0], ResolutionPreset.high);
    _initializeControllerFuture = _initCameraAndServices();
    _expiryTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted &&
          _trackingFrame != null &&
          (_trackingClock.elapsedMicroseconds - _trackingFrame!.timestampUs >
                  500000 ||
              _trackingOrientation != _controller.value.deviceOrientation ||
              !_visible ||
              !_foreground ||
              _busy ||
              _recording)) {
        setState(() {
          _trackingFrame = null;
          _trackingFps = 0;
        });
      }
    });
  }

  Future<void> _initCameraAndServices() async {
    await _controller.initialize();
    if (!mounted) return;
    await _handDetectorService.init();
    if (!mounted) {
      _handDetectorService.close();
      return;
    }
    await _poseService.initialize();

    if (mounted && _foreground && _visible) {
      await _controller.startImageStream(_processLiveCameraFrame);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      trackingRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) trackingRouteObserver.subscribe(this, route);
    }
  }

  void _invalidateTracking() {
    _epoch++;
    if (mounted) {
      setState(() {
        _trackingFrame = null;
        _trackingFps = 0;
      });
    }
  }

  @override
  void didPushNext() {
    _visible = false;
    _invalidateTracking();
  }

  @override
  void didPopNext() {
    _visible = true;
    _invalidateTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidateTracking();
    final resume = _foreground;
    _lifecycle = _lifecycle.then((_) async {
      try {
        await _initializeControllerFuture;
        if (!mounted) return;
        if (!resume) {
          if (_controller.value.isStreamingImages) {
            await _controller.stopImageStream();
          }
          await _controller.pausePreview();
          if (!_uploading) await _poseService.close();
        } else {
          if (!_uploading) await _poseService.initialize();
          if (!mounted || !_foreground) return;
          await _controller.resumePreview();
          if (!_uploading && !_controller.value.isStreamingImages) {
            await _controller.startImageStream(_processLiveCameraFrame);
          }
        }
      } catch (e) {
        debugPrint('Tracking lifecycle: $e');
      }
    });
  }

  void _processLiveCameraFrame(CameraImage image) async {
    final now = _trackingClock.elapsedMicroseconds;
    if (_isProcessingLiveFrame ||
        _busy ||
        _recording ||
        !_visible ||
        !_foreground ||
        now - _lastTrackingUs < 100000) {
      return;
    }
    _isProcessingLiveFrame = true;
    _lastTrackingUs = now;
    final epoch = _epoch;
    final orientation = _controller.value.deviceOrientation;
    final description = widget.cameras[0];
    final front = description.lensDirection == CameraLensDirection.front;
    try {
      final result = await _poseService.detect(
        image,
        rotation: poseRotation(
          description.sensorOrientation,
          orientation,
          front,
        ),
        mirror: front,
        frameId: ++_frameId,
        timestampUs: now,
      );
      if (!mounted ||
          epoch != _epoch ||
          !_visible ||
          !_foreground ||
          _busy ||
          _recording) {
        return;
      }
      final completed = _trackingClock.elapsedMicroseconds;
      final fresh =
          completed - now <= 500000 &&
          orientation == _controller.value.deviceOrientation;
      debugPrint(
        'KSL_PREVIEW frameId=${result?.frameId} face=${result?.face.length ?? 0} fresh=$fresh latencyMs=${(completed - now) / 1000}',
      );
      // Choose one identified hand for the existing classifier; never concatenate hands/body.
      final selected = fresh ? (result?.rightHand ?? result?.leftHand) : null;
      final classification = _handDetectorService.classifyLandmarks(
        selected?.landmarks,
      );
      setState(() {
        _trackingFrame = fresh ? result : null;
        _trackingOrientation = orientation;
        _trackingFps = _lastCompletionUs == 0
            ? 0
            : 1000000 / (completed - _lastCompletionUs);
        _lastCompletionUs = completed;
        _hasHand = classification.hasHand;
        _currentLandmarks = classification.landmarks;
        _predictedFingers = classification.predictedSign;
        _predictedLabel = classification.predictedLabel;
      });
      if (_frameId % 30 == 0) {
        debugPrint(
          '[tracking] frame=$_frameId latencyMs=${(completed - now) / 1000} fps=${_trackingFps.toStringAsFixed(1)} body=${result?.body.length ?? 0} left=${result?.leftHand?.landmarks.length ?? 0} right=${result?.rightHand?.landmarks.length ?? 0}',
        );
      }
    } catch (e) {
      if (mounted) _invalidateTracking();
      debugPrint('Error processing tracking frame: $e');
    } finally {
      _isProcessingLiveFrame = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    trackingRouteObserver.unsubscribe(this);
    _expiryTimer?.cancel();
    _epoch++;
    if (_controller.value.isStreamingImages) {
      _controller.stopImageStream();
    }
    _handDetectorService.close();
    unawaited(_poseService.close());
    _controller.dispose();
    super.dispose();
  }

  bool _recording = false;
  bool _busy = false;
  bool _uploading = false;

  Future<void> _uploadVideo() async {
    if (_busy || _recording || _controller.value.isRecordingVideo) return;
    _invalidateTracking();
    setState(() {
      _busy = true;
      _uploading = true;
    });
    try {
      await _initializeControllerFuture;
      if (_controller.value.isStreamingImages) {
        await _controller.stopImageStream();
      }
      final uri = await const MethodChannel(
        'com.example.signlanguage/video_picker',
      ).invokeMethod<String>('pickVideo');
      await _lifecycle;
      if (!mounted || uri == null) return;
      await _poseService.initialize();
      if (_poseService.error != null) throw StateError(_poseService.error!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoAnalysisPage(uri: uri, detector: _handDetectorService),
        ),
      );
    } catch (e) {
      debugPrint('[video upload] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open video. Please try again.'),
          ),
        );
      }
    } finally {
      _uploading = false;
      if (mounted) {
        try {
          await _lifecycle;
          await _poseService.initialize();
          if (mounted &&
              _foreground &&
              _controller.value.isInitialized &&
              !_controller.value.isStreamingImages) {
            await _controller.startImageStream(_processLiveCameraFrame);
          }
        } catch (e) {
          debugPrint('[video upload] camera resume failed: $e');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }
  }

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
    widget.onVideoSaved?.call();
  }

  Future<void> _analyzeAndPublish(XFile mediaFile, bool isVideo) async {
    try {
      final result = await _handDetectorService.analyzeImageFile(
        mediaFile.path,
      );

      if (mounted) {
        setState(() {
          _hasHand = result.hasHand;
          _currentLandmarks = result.landmarks;
          _predictedFingers = result.predictedSign;
          _predictedLabel = result.predictedLabel;
          _debugLogs = result.logs;
        });

        final text = result.hasHand && result.predictedSign >= 0
            ? '손 동작: ${result.predictedLabel}'
            : 'No hand detected';

        widget.onRecognitionResult?.call(text);
      }
    } catch (e) {
      debugPrint('Error analyzing captured file: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (_busy || _recording || _controller.value.isRecordingVideo) return;
    if (!_ready) {
      _showError('Camera is not ready');
      return;
    }
    _invalidateTracking();
    setState(() => _busy = true);
    try {
      final photo = await _controller.takePicture();
      unawaited(_checkPhotoFile(photo));
      unawaited(_savePhotoToGallery(photo));

      await _analyzeAndPublish(photo, false);

      _publish(photo, false);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPhotoFile(XFile photo) async {
    try {
      final bytes = await photo.length();
      debugPrint('[photo] file size: $bytes bytes, path: ${photo.path}');
    } catch (error) {
      debugPrint('[photo] file missing: ${photo.path}; $error');
    }
  }

  Future<void> _savePhotoToGallery(XFile photo) async {
    try {
      await Gal.putImage(photo.path);
      debugPrint('[photo] Gallery save success: ${photo.path}');
    } catch (error) {
      debugPrint('[photo] Gallery save failure: $error');
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || _controller.value.isRecordingVideo) return;
    if (!_ready) {
      _showError('Camera is not ready');
      return;
    }
    _held = true;
    _invalidateTracking();
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
    if (mounted && !_held && _recording) await _stopRecording();
  }

  void _releaseRecording() {
    _held = false;
    if (mounted) setState(() => _pressed = false);
    if (_recording && !_busy) _stopRecording();
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    _invalidateTracking();
    setState(() => _busy = true);
    try {
      final video = await _controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      await Gal.putVideo(video.path);

      await _analyzeAndPublish(video, true);

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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_controller),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: TrackingPainter(
                                _busy || _recording || !_foreground || !_visible
                                    ? null
                                    : _trackingFrame,
                                debugFacePoints: _debugFacePoints,
                              ),
                            ),
                          ),
                        ],
                      ),
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
          if (_poseService.error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: stripHeight + 140,
              child: IgnorePointer(
                child: Text(
                  _poseService.error!,
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: textShadow,
                  ),
                ),
              ),
            ),
          // Debug Overlay
          Positioned(
            left: 16,
            top: 80,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DebugOverlay(
                    faceLandmarkCount: _trackingFrame?.face.length ?? 0,
                    faceDots: _debugFacePoints,
                    onToggleFaceDots: () =>
                        setState(() => _debugFacePoints = !_debugFacePoints),
                    hasHand: _hasHand,
                    landmarkCount: _currentLandmarks?.length ?? 0,
                    fps: _trackingFps,
                    fingerCount: _predictedFingers,
                  ),
                  if (_debugLogs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 280,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(200),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.cyanAccent.withAlpha(100),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '--- PIPELINE DEBUG LOGS ---',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          ..._debugLogs.map(
                            (log) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                              ),
                              child: Text(
                                '${log.stage}: ${log.details}',
                                style: TextStyle(
                                  color: log.success
                                      ? Colors.greenAccent
                                      : Colors.amberAccent,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 240,
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(178),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasHand
                          ? const Color(0xFF00E676)
                          : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _hasHand && _predictedFingers >= 0
                        ? '🖐 Sign Detected: $_predictedLabel'
                        : 'No hand detected',
                    style: TextStyle(
                      color: _hasHand ? Colors.white : Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: textShadow,
                    ),
                  ),
                ),
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
                    const Flexible(
                      child: Text(
                        'KEYPOINT CLASSIFIER',
                        style: TextStyle(
                          color: Color(0xFF6A818C),
                          fontSize: 12,
                          letterSpacing: 2.5,
                          shadows: textShadow,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      label: const Text('Upload'),
                      onPressed: _busy || _recording ? null : _uploadVideo,
                      icon: const Icon(Icons.video_library_outlined),
                    ),
                    const SizedBox(width: 8),
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
                        ? '분석 중…'
                        : _recording
                        ? '녹화 중'
                        : _hasHand && _predictedFingers >= 0
                        ? '손 동작: $_predictedLabel'
                        : '손 동작을 보여주세요',
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
                Text(
                  _hasHand && _predictedFingers >= 0
                      ? 'Detected Sign: $_predictedLabel'
                      : 'Pointing / Close / Open',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    shadows: textShadow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _busy
                      ? '이미지 분석 및 결과 생성 중...'
                      : _recording
                      ? '손을 떼면 녹화가 종료됩니다'
                      : '탭하여 촬영/분석 · 길게 눌러 녹화',
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
                    'Keypoint Classifier: Pointing / Close / Open',
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
