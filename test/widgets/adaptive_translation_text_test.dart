import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(
      tester.widget<Text>(textFinder).data!.replaceAll('\u2060', ''),
      short,
    );
    expect(tester.widget<Text>(textFinder).data, contains('아\u2060이\u2060스'));

    await tester.pumpWidget(host(long));
    expect(tester.getSemantics(textFinder).label, long);
    expect(
      tester.widget<Text>(textFinder).data!.replaceAll('\u2060', ''),
      long,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits text without layout overflow', (tester) async {
    await tester.pumpWidget(host(long, size: const Size(80, 40), scale: 3));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(textFinder).textAlign, TextAlign.center);
  });
  testWidgets('full Korean result wraps entirely within a narrow phone area', (
    tester,
  ) async {
    const sentence =
        '북태평양쪽에서 다가오는 기압골의 영향을 받겠습니다. 점차 그 가장자리에 들겠습니다. 남부지방은 고기압이 유입되겠습니다. 입니다.';
    const size = Size(320, 180);
    expect(sentence.length, 71);
    await tester.pumpWidget(host(sentence, size: size));

    final text = tester.widget<Text>(textFinder);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: textFinder, matching: find.byType(RichText)),
    );
    expect(text.data!.replaceAll('\u2060', ''), sentence);
    expect(tester.getSemantics(textFinder).label, sentence);
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.data!.length),
    );
    expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(-0.01));
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
      expect(box.top, greaterThanOrEqualTo(-0.01));
      expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
    }
    expect(paragraph.size.width, lessThanOrEqualTo(size.width));
    expect(paragraph.size.height, lessThanOrEqualTo(size.height));
    final lastCharacter = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: text.data!.length - 1,
        extentOffset: text.data!.length,
      ),
    );
    expect(lastCharacter, isNotEmpty);
    expect(lastCharacter.last.bottom, lessThanOrEqualTo(size.height));
    expect(tester.takeException(), isNull);
  });

}
