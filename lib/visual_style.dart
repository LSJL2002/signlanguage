import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const ink = Color(0xFF354B59);
  static const muted = Color(0xFF637B88);
  static const accent = Color(0xFF52788C);
  static const paper = Color(0xFFF4F6F3);
  static const wash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE2EBEF), Color(0xFFF8F5EF), Color(0xFFE5EEEA)],
  );
}

class SoftBackground extends StatelessWidget {
  const SoftBackground({super.key, this.child});
  final Widget? child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: AppPalette.wash),
    child: child,
  );
}
