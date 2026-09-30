import 'package:flutter/material.dart';

class AdaptiveTranslationText extends StatelessWidget {
  const AdaptiveTranslationText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const baseStyle = TextStyle(
          color: Color(0xFF20262B),
          fontWeight: FontWeight.w400,
          height: 1.3,
          letterSpacing: -0.4,
        );
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final displayText = text.replaceAllMapped(
          RegExp(r'[가-힣]+'),
          (match) => match[0]!.split('').join('\u2060'),
        );
        bool fits(double size) {
          final painter = TextPainter(
            text: TextSpan(
              text: displayText,
              style: baseStyle.copyWith(fontSize: size),
            ),
            textDirection: direction,
            textAlign: TextAlign.center,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final result =
              painter.height <= constraints.maxHeight &&
              painter.width <= constraints.maxWidth;
          painter.dispose();
          return result;
        }

        var lower = 1.0;
        var upper = 72.0;
        for (var step = 0; step < 16; step++) {
          final middle = (lower + upper) / 2;
          if (fits(middle)) {
            lower = middle;
          } else {
            upper = middle;
          }
        }
        return Center(
          child: Text(
            displayText,
            semanticsLabel: text,
            key: const Key('translationText'),
            textAlign: TextAlign.center,
            softWrap: false,
            style: baseStyle.copyWith(fontSize: lower),
          ),
        );
      },
    );
  }
}
