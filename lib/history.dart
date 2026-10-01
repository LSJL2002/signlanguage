import 'package:flutter/material.dart';

import 'visual_style.dart';

class RecognitionRecord {
  const RecognitionRecord(this.recognizedText, this.timestamp);

  final String recognizedText;
  final DateTime timestamp;
}

/// Session-only history. Each add represents a new result, even for equal text.
class RecognitionHistory extends ChangeNotifier {
  final List<RecognitionRecord> _records = [];

  List<RecognitionRecord> get records => List.unmodifiable(_records);

  void add(String recognizedText) {
    if (recognizedText.trim().isEmpty) return;
    _records.insert(0, RecognitionRecord(recognizedText, DateTime.now()));
    notifyListeners();
  }
}

final recognitionHistory = RecognitionHistory();

class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key, this.history});

  final RecognitionHistory? history;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '기록 / History',
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xB3FFFFFF),
      foregroundColor: AppPalette.accent,
      minimumSize: const Size(48, 48),
    ),
    icon: const Icon(Icons.history),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(history: history ?? recognitionHistory),
      ),
    ),
  );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.history});

  final RecognitionHistory history;

  String _format(DateTime timestamp) {
    final t = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: const Text(
        '기록 / History',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppPalette.ink,
    ),
    body: SoftBackground(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: history,
          builder: (context, child) {
            final records = history.records;
            if (records.isEmpty) {
              return const Center(child: Text('아직 기록이 없습니다.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xBFFFFFFF),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xE6FFFFFF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0852788C),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.recognizedText,
                        style: const TextStyle(
                          color: AppPalette.ink,
                          fontSize: 17,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _format(record.timestamp),
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
