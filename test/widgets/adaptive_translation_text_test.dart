import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signlanguage/widgets/adaptive_translation_text.dart';

Widget host(String text, {Size size = const Size(320, 180), double scale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: AdaptiveTranslationText(text: text),
        ),
      ),
    ),
  );
}

void main() {
  const short = '아이스 아메리카노 한 잔 주세요.';
  final long = List.filled(8, short).join(' ');
  final textFinder = find.byKey(const Key('translationText'));

  testWidgets('preserves source semantics and updates caller text', (
    tester,
  ) async {
    await tester.pumpWidget(host(short));
    expect(tester.getSemantics(textFinder).label, short);
    expect(tester.widget<Text>(textFinder).data, short);
    expect(tester.widget<Text>(textFinder).softWrap, isTrue);

    await tester.pumpWidget(host(long));
    expect(tester.getSemantics(textFinder).label, long);
    expect(tester.widget<Text>(textFinder).data, long);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long sentences remain accessible by scrolling', (tester) async {
    final sentence = List.filled(30, short).join(' ');
    await tester.pumpWidget(host(sentence, size: const Size(240, 100)));

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<SingleChildScrollView>(
        find.byKey(const Key('translationScrollView')),
      ),
      isNotNull,
    );
    expect(tester.widget<Text>(textFinder).data, sentence);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('translationScrollView')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const Key('translationScrollView')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
