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
}
