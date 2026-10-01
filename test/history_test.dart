import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/history.dart';
import 'package:signlanguage/main.dart';

void main() {
  test(
    'history timestamps every result, keeps duplicates and newest first',
    () {
      final history = RecognitionHistory();
      addTearDown(history.dispose);
      final before = DateTime.now();
      history.add('first');
      history.add('second');
      history.add('second');
      history.add('   ');
      expect(history.records.map((r) => r.recognizedText), [
        'second',
        'second',
        'first',
      ]);
      expect(history.records.first.timestamp.isBefore(before), isFalse);
      expect(history.records.first.timestamp.isAfter(DateTime.now()), isFalse);
      expect(() => history.records.clear(), throwsUnsupportedError);
    },
  );

  testWidgets(
    'result saves on arrival and change, not rebuild or history return',
    (tester) async {
      final history = RecognitionHistory();
      addTearDown(history.dispose);
      Widget app(String text) => MaterialApp(
        home: CommunicationPage(recognizedText: text, history: history),
      );
      await tester.pumpWidget(app('첫 번째'));
      await tester.pumpWidget(app('첫 번째'));
      expect(history.records.length, 1);
      await tester.pumpWidget(app('두 번째'));
      expect(history.records.length, 2);
      await tester.tap(find.byTooltip('기록 / History'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.text('두 번째'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('두 번째')).dy,
        lessThan(tester.getTopLeft(find.text('첫 번째')).dy),
      );
      expect(
        find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2} ')),
        findsNWidgets(2),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('다시 하기 / Try Again'), findsOneWidget);
      expect(history.records.length, 2);
      // A separate result arrival may legitimately contain the same text.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app('두 번째'));
      expect(history.records.length, 3);
    },
  );

  testWidgets('empty history updates and scrolls to older records', (
    tester,
  ) async {
    final history = RecognitionHistory();
    addTearDown(history.dispose);
    await tester.pumpWidget(MaterialApp(home: HistoryPage(history: history)));
    expect(find.text('아직 기록이 없습니다.'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      history.add('result $i');
    }
    await tester.pump();
    expect(find.text('result 39'), findsOneWidget);
    expect(find.text('result 0'), findsNothing);
    await tester.scrollUntilVisible(find.text('result 0'), 400);
    expect(find.text('result 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
