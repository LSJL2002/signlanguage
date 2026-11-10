import 'package:flutter/material.dart';

class AdaptiveTranslationText extends StatelessWidget {
  const AdaptiveTranslationText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minimumFontSize = 24.0;
        const baseStyle = TextStyle(
          color: Color(0xFF20262B),
          fontWeight: FontWeight.w400,
          height: 1.3,
          letterSpacing: -0.4,
        );
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        bool fits(double size) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: baseStyle.copyWith(fontSize: size),
            ),
            textDirection: direction,
            textAlign: TextAlign.center,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final result = painter.height <= constraints.maxHeight;
          painter.dispose();
          return result;
        }

        var lower = minimumFontSize;
        var upper = 72.0;
        final minimumFits = fits(minimumFontSize);
        for (var step = 0; step < 16; step++) {
          final middle = (lower + upper) / 2;
          if (fits(middle)) {
            lower = middle;
          } else {
            upper = middle;
          }
        }
        final fontSize = minimumFits ? lower : minimumFontSize;
        return SingleChildScrollView(
          key: const Key('translationScrollView'),
          child: SizedBox(
            width: constraints.maxWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Text(
                  text,
                  key: const Key('translationText'),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: baseStyle.copyWith(fontSize: fontSize),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
