import 'package:flutter/material.dart';

import 'services/text_to_sign_service.dart';
import 'visual_style.dart';
import 'widgets/sign_skeleton_painter.dart';

/// Type a Korean sentence -> see the predicted glosses and the generated signing motion.
class TextToSignPage extends StatefulWidget {
  const TextToSignPage({super.key});

  @override
  State<TextToSignPage> createState() => _TextToSignPageState();
}

class _TextToSignPageState extends State<TextToSignPage>
    with SingleTickerProviderStateMixin {
  final _service = TextToSignService();
  final _text = TextEditingController();
  late final AnimationController _player;

  TextToSignResult? _result;
  bool _loading = false;
  String? _error;
  double _playbackSpeed = 1.0;

  static const _examples = [
    '내일 전국이 대체로 맑겠습니다.',
    '아침 최저기온은 16도에서 21도가 되겠습니다.',
    '중부지방은 구름이 많겠습니다.',
  ];

  @override
  void initState() {
    super.initState();
    _player = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _player.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final sentence = _text.text.trim();
    if (sentence.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    _player.stop();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.generate(sentence);
      if (!mounted) return;
      setState(() => _result = result);
      _restart();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _restart() {
    final result = _result;
    if (result == null || result.frames == 0) return;
    _player.duration = result.length * (1 / _playbackSpeed);
    _player
      ..reset()
      ..repeat();
    setState(() {});
  }

  void _togglePlay() {
    if (_player.isAnimating) {
      _player.stop();
    } else {
      _player.repeat();
    }
    setState(() {});
  }

  void _setSpeed(double speed) {
    final progress = _player.value;
    final playing = _player.isAnimating;
    setState(() => _playbackSpeed = speed);
    final result = _result;
    if (result == null) return;
    _player.duration = result.length * (1 / speed);
    _player.value = progress;
    if (playing) _player.repeat();
  }

  int get _frame {
    final result = _result;
    if (result == null || result.frames == 0) return 0;
    return (_player.value * result.frames).floor().clamp(0, result.frames - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('문장 → 수어')),
      body: SoftBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _inputCard(),
              const SizedBox(height: 16),
              if (_loading) _loadingCard(),
              if (_error != null) _errorCard(_error!),
              if (_result != null && !_loading) ..._resultView(_result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputCard() => Card(
    elevation: 0,
    color: const Color(0xD9FFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _generate(),
            decoration: const InputDecoration(
              labelText: '한국어 문장을 입력하세요',
              hintText: '예: 내일 전국이 대체로 맑겠습니다.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final example in _examples)
                ActionChip(
                  label: Text(example, style: const TextStyle(fontSize: 12)),
                  onPressed: _loading ? null : () => setState(() => _text.text = example),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: const Icon(Icons.sign_language),
            label: const Text('수어로 변환'),
          ),
        ],
      ),
    ),
  );

  Widget _loadingCard() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          '수어 동작을 만드는 중…\n처음 실행할 때는 모델 준비로 시간이 걸릴 수 있어요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppPalette.muted),
        ),
      ],
    ),
  );

  Widget _errorCard(String message) => Card(
    elevation: 0,
    color: const Color(0xFFFDECEA),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB3261E)),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );

  List<Widget> _resultView(TextToSignResult result) => [
    AnimatedBuilder(
      animation: _player,
      builder: (context, _) {
        final frame = _frame;
        final current = result.glossIndexAt(frame);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CustomPaint(
                    painter: SignSkeletonPainter(result: result, frame: frame),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result.glosses.isEmpty ? '' : result.glosses[current],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < result.glosses.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: i == current ? AppPalette.accent : const Color(0xCCFFFFFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      result.glosses[i],
                      style: TextStyle(
                        color: i == current ? Colors.white : AppPalette.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _player.value,
              onChanged: (value) {
                _player.stop();
                _player.value = value;
                setState(() {});
              },
            ),
            Text(
              '프레임 ${frame + 1} / ${result.frames}  ·  '
              '${(result.frames / TextToSignResult.fps).toStringAsFixed(1)}초',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppPalette.muted, fontSize: 12),
            ),
          ],
        );
      },
    ),
    const SizedBox(height: 8),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: '처음부터',
          onPressed: _restart,
          icon: const Icon(Icons.replay),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: _player.isAnimating ? '일시정지' : '재생',
          onPressed: _togglePlay,
          icon: Icon(_player.isAnimating ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 16),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0.5, label: Text('0.5x')),
            ButtonSegment(value: 1.0, label: Text('1x')),
            ButtonSegment(value: 1.5, label: Text('1.5x')),
          ],
          selected: {_playbackSpeed},
          onSelectionChanged: (s) => _setSpeed(s.first),
        ),
      ],
    ),
  ];
}
