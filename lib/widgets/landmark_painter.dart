import 'package:flutter/material.dart';

class LandmarkPainter extends CustomPainter {
  final List<Map<String, double>>? landmarks;

  LandmarkPainter(this.landmarks);

  static const List<List<int>> connections = [
    // Thumb
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Index finger
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Middle finger
    [5, 9], [9, 10], [10, 11], [11, 12],
    // Ring finger
    [9, 13], [13, 14], [14, 15], [15, 16],
    // Pinky finger
    [13, 17], [17, 18], [18, 19], [19, 20],
    // Palm base
    [0, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks == null || landmarks!.isEmpty) return;

    final linePaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = const Color(0xFFFF3D00)
      ..style = PaintingStyle.fill;

    // Draw connection lines
    for (final conn in connections) {
      final int startIdx = conn[0];
      final int endIdx = conn[1];

      if (startIdx < landmarks!.length && endIdx < landmarks!.length) {
        final start = landmarks![startIdx];
        final end = landmarks![endIdx];

        final startPoint = Offset(start['x']! * size.width, start['y']! * size.height);
        final endPoint = Offset(end['x']! * size.width, end['y']! * size.height);

        canvas.drawLine(startPoint, endPoint, linePaint);
      }
    }

    // Draw landmark points
    for (final lm in landmarks!) {
      final point = Offset(lm['x']! * size.width, lm['y']! * size.height);
      canvas.drawCircle(point, 5.0, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LandmarkPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks;
  }
}
