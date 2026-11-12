import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';

import 'widgets/adaptive_translation_text.dart';
import 'history.dart';
import 'visual_style.dart';
import 'services/hand_detector_service.dart';
import 'widgets/translation_mode_pill.dart';
import 'services/video_prediction_api.dart';
import 'services/pose_service.dart';
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
    debugPrint('KSL_RESULT_UI chars=${widget.recognizedText.length} text=${widget.recognizedText}');
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
  final VideoPredictionApi? predictionApi;
  final VoidCallback? onVideoSaved;
  final void Function(XFile file, bool isVideo)? onMediaCaptured;
  final void Function(String recognizedText)? onRecognitionResult;

  const CameraScreen({
    super.key,
    required this.cameras,
    this.predictionApi,
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
  final VideoPredictionClient _predictionClient = VideoPredictionClient(
    baseUrl: configuredApiBaseUrl,
    apiToken: configuredApiToken,
  );

  final HandDetectorService _handDetectorService = HandDetectorService();

  final PoseService _poseService = PoseService();
  bool isOnlineMode = false;
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
  // Retained for console diagnostics; not rendered over the preview.
  // ignore: unused_field
  List<Map<String, double>>? _currentLandmarks;
  int _predictedFingers = -1;
  // ignore: unused_field
  String _predictedLabel = '';

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
    if (!resume) {
      _cancelRecording = true;
      if (_recording && !_busy) unawaited(_stopRecording());
    }
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
          '[tracking] frame=$_frameId latencyMs=${(completed - now) / 1000} fps=${_trackingFps.toStringAsFixed(1)} body=${result?.body.length ?? 0} left=${result?.leftHand?.landmarks.length ?? 0} right=${result?.rightHand?.landmarks.length ?? 0} hasHand=$_hasHand fingers=$_predictedFingers',
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
    _predictionClient.close();
    _controller.dispose();
    super.dispose();
  }

  bool _recording = false;
  bool _busy = false;
  bool _uploading = false;

  Future<void> _uploadVideoOnline({XFile? recordedVideo}) async {
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
      final pickedVideo = recordedVideo == null
          ? await FilePicker.pickFile(type: FileType.video)
          : null;
      await _lifecycle;
      if (!mounted || (recordedVideo == null && pickedVideo == null)) return;
      final size = recordedVideo != null
          ? await recordedVideo.length()
          : await pickedVideo!.length();
      if (size == null || size <= 0) {
        throw const VideoPredictionException(
          'The selected video could not be read. Choose it again and try once more.',
        );
      }
      if (!mounted) return;

      final uploadProgress =
          ValueNotifier<({int sent, int total, bool waiting})>((
            sent: 0,
            total: size,
            waiting: false,
          ));
      var progressDialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Uploading video'),
              content:
                  ValueListenableBuilder<({int sent, int total, bool waiting})>(
                    valueListenable: uploadProgress,
                    builder: (context, progress, _) {
                      final fraction = progress.total == 0
                          ? null
                          : (progress.sent / progress.total).clamp(0.0, 1.0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            recordedVideo?.name ?? pickedVideo!.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: progress.waiting ? null : fraction,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            progress.waiting
                                ? 'Video sent. Waiting for prediction…'
                                : fraction == null
                                ? 'Preparing video…'
                                : 'Uploading ${(fraction * 100).floor()}%',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        ),
      );
      try {
        final result = await (widget.predictionApi ?? _predictionClient)
            .predict(
              recordedVideo?.openRead() ?? pickedVideo!.readAsByteStream(),
              size: size,
              onProgress: (sent, total) {
                uploadProgress.value = (
                  sent: sent,
                  total: total,
                  waiting: sent >= total,
                );
              },
            );
        if (!mounted) return;
        progressDialogOpen = false;
        Navigator.of(context).pop();
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CommunicationPage(recognizedText: result.sentence),
          ),
        );
      } finally {
        uploadProgress.dispose();
        if (progressDialogOpen && mounted) {
          progressDialogOpen = false;
          Navigator.of(context).pop();
        }
      }
    } on VideoPredictionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The video picker could not be opened. Please try again.',
            ),
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video selection is not available on this device.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[video upload] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to upload video. Please try again.'),
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

  Future<void> _uploadVideo({XFile? recordedVideo}) async {
    // Select once: later toggle changes do not reroute an in-flight request.
    if (isOnlineMode) {
      return _uploadVideoOnline(recordedVideo: recordedVideo);
    }
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
      final uri =
          recordedVideo?.path ??
          await const MethodChannel('com.example.signlanguage/video_picker')
              .invokeMethod<String>('pickVideo');
      await _lifecycle;
      if (!mounted || uri == null) return;
      await _poseService.initialize();
      if (_poseService.error != null) throw StateError(_poseService.error!);
      if (!mounted) return;
      final sentence = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) =>
              VideoAnalysisPage(uri: uri, detector: _handDetectorService),
        ),
      );
      if (mounted && sentence != null && sentence.trim().isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CommunicationPage(recognizedText: sentence),
          ),
        );
      }
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

  bool _cancelRecording = false;

  bool get _ready => _controller.value.isInitialized;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Capture/save failed: $error')));
  }

  void _toggleRecording() {
    if (_busy) return;
    if (_recording) {
      unawaited(_stopRecording());
    } else {
      unawaited(_startRecording());
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || _controller.value.isRecordingVideo) return;
    if (!_ready) {
      _showError('Camera is not ready');
      return;
    }
    _cancelRecording = false;
    _invalidateTracking();
    setState(() => _busy = true);
    try {
      if (_controller.value.isStreamingImages) {
        await _controller.stopImageStream();
      }
      await _controller.startVideoRecording();
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (error) {
      _showError(error);
    } finally {
      await _resumePreviewAfterRecording();
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _cancelRecording && _recording) {
      await _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    _invalidateTracking();
    setState(() => _busy = true);
    try {
      final video = await _controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      if (_cancelRecording || !_foreground) return;
      if (await video.length() <= 0) {
        throw StateError('The recording is empty. Please record again.');
      }
      if (!mounted || _cancelRecording || !_foreground) return;
      // Gallery saving is secondary; the captured file remains the input.
      unawaited(_saveRecordedVideo(video));
      widget.onMediaCaptured?.call(video, true);
      setState(() => _busy = false);
      await _uploadVideo(recordedVideo: video);
    } catch (error) {
      if (mounted) {
        setState(() => _recording = _controller.value.isRecordingVideo);
      }
      _showError(error);
    } finally {
      await _resumePreviewAfterRecording();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumePreviewAfterRecording() async {
    if (!mounted ||
        !_foreground ||
        !_ready ||
        _recording ||
        _uploading ||
        _controller.value.isRecordingVideo ||
        _controller.value.isStreamingImages) {
      return;
    }
    try {
      await _controller.startImageStream(_processLiveCameraFrame);
    } catch (error) {
      debugPrint('[recording] Preview resume failed: $error');
    }
  }

  Future<void> _saveRecordedVideo(XFile video) async {
    try {
      await Gal.putVideo(video.path);
    } catch (error) {
      debugPrint('[recording] Gallery save failed: $error');
    }
  }

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
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
            bottom: MediaQuery.paddingOf(context).bottom + 220,
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
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '수어를 보여주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      shadows: textShadow,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final pillWidth = ((constraints.maxWidth - 96) / 2 - 12)
                          .clamp(0.0, 96.0);
                      return SizedBox(
                        height: 96,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: Semantics(
                                button: true,
                                enabled: !_busy,
                                label: _recording
                                    ? 'Stop recording'
                                    : 'Start recording',
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
                                        onTapDown: (_) =>
                                            setState(() => _pressed = true),
                                        onTapUp: (_) =>
                                            setState(() => _pressed = false),
                                        onTapCancel: () =>
                                            setState(() => _pressed = false),
                                        onTap: _toggleRecording,
                                        child: Center(
                                          child: _busy
                                              ? const SizedBox(
                                                  width: 36,
                                                  height: 36,
                                                  child:
                                                      CircularProgressIndicator(
                                                        key: Key(
                                                          'recordLoading',
                                                        ),
                                                        strokeWidth: 2,
                                                        color: Color(
                                                          0xFF46565D,
                                                        ),
                                                      ),
                                                )
                                              : Container(
                                                  key: const Key('recordShape'),
                                                  width: _recording ? 32 : 66,
                                                  height: _recording ? 32 : 66,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFEE7B6E,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          _recording ? 8 : 40,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFBA625B,
                                                      ),
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
                            ),
                            Positioned(
                              right: 0,
                              width: pillWidth,
                              top: 24,
                              height: 48,
                              child: TranslationModePill(
                                isOnlineMode: isOnlineMode,
                                onChanged: (value) =>
                                    setState(() => isOnlineMode = value),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '녹화',
                    key: Key('recordLabel'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: textShadow,
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
