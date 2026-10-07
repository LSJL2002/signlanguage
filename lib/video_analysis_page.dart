import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'services/hand_detector_service.dart';
import 'services/video_analysis_service.dart';
import 'widgets/pose_painter.dart';

class VideoAnalysisPage extends StatefulWidget {
  const VideoAnalysisPage({
    super.key,
    required this.uri,
    required this.detector,
  });
  final String uri;
  final HandDetectorService detector;
  @override
  State<VideoAnalysisPage> createState() => _VideoAnalysisPageState();
}

class _VideoAnalysisPageState extends State<VideoAnalysisPage>
    with WidgetsBindingObserver {
  late final VideoAnalysisService _service;
  late final Future<void> _task;
  VideoAnalysisUpdate? _latest;
  bool _done = false;
  bool _leaving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = VideoAnalysisService(
      classify: widget.detector.classifyLandmarks,
    );
    _task = _run();
  }

  Future<void> _run() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final folder = await Directory('${directory.path}/video_analysis')
          .create(recursive: true);
      final output = File(
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jsonl',
      );
      debugPrint('[video analysis] output=${output.path}');
      await _service.analyze(widget.uri, output, (update) {
        if (mounted) setState(() => _latest = update);
      });
      debugPrint(
        '[video analysis] frames=${_latest?.completed ?? 0} cancelled=${_service.cancelled} output=${output.path}',
      );
    } catch (e, stack) {
      debugPrint('KSL_VIDEO_ERROR page exception=$e stack=$stack');
      _error = e is PlatformException ? (e.message ?? e.code) : e.toString();
    } finally {
      if (mounted) setState(() => _done = true);
    }
  }

  Future<void> _exit() async {
    if (_leaving) return;
    _leaving = true;
    _service.cancelled = true;
    await _task;
    if (mounted) {
      setState(() => _done = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _service.cancelled = true;
  }

  @override
  void dispose() {
    _service.cancelled = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _latest;
    final progress = data == null ? 0.0 : data.completed / data.total;
    final status =
        _error ??
        (_done
            ? (_service.cancelled ? 'Analysis stopped' : 'Analysis complete')
            : 'Analyzing ${(progress * 100).floor()}%');
    return PopScope(
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Video analysis')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: data?.preview == null
                        ? (_done
                              ? const Icon(Icons.video_file_outlined, size: 64)
                              : const CircularProgressIndicator())
                        : AspectRatio(
                            aspectRatio: data!.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  data.preview!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                                CustomPaint(
                                  painter: TrackingPainter(data.frame),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(status, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress),
                if (data != null)
                  Text(
                    '${data.completed} / ${data.total} frames · ${data.label}',
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _exit,
                  child: Text(_done ? 'Done' : 'Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
