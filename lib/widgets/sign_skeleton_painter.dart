import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/text_to_sign_service.dart';

/// Draws one frame of generated keypoints as a 2D stick figure.
///
/// Layout (same as the training data):
///   0–10    body: nose, neck, R shoulder, R elbow, R wrist,
///           L shoulder, L elbow, L wrist, mid-hip, R hip, L hip
///   11–80   face, 70-point layout (jaw, brows, nose, eyes, lips, pupils)
///   81–101  hand (21 points)
///   102–122 hand (21 points)
class SignSkeletonPainter extends CustomPainter {
  SignSkeletonPainter({
    required this.result,
    required this.frame,
    this.bodyColor = const Color(0xFF52788C),
    this.handColorA = const Color(0xFFE07A5F),
    this.handColorB = const Color(0xFF3D9970),
    this.faceColor = const Color(0xFF637B88),
  });

  final TextToSignResult result;
  final int frame;
  final Color bodyColor;
  final Color handColorA;
  final Color handColorB;
  final Color faceColor;

  // Fixed view box in model coordinates, so the figure doesn't jump between frames.
  static const _minX = -1.45, _maxX = 1.45, _minY = -1.1, _maxY = 1.8;

  static const _faceStart = 11, _handA = 81, _handB = 102;
  static const _bodyWrists = [4, 7];

  static const _bodyBones = [
    [0, 1], [1, 2], [2, 3], [3, 4], [1, 5], [5, 6], [6, 7],
    [1, 8], [8, 9], [8, 10], [2, 9], [5, 10],
  ];
  static const _handBones = [
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [5, 9], [9, 10], [10, 11], [11, 12], // middle
    [9, 13], [13, 14], [14, 15], [15, 16], // ring
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // pinky + palm
  ];
  // Face polylines (start, end inclusive, closed?)
  static const _faceLines = [
    [0, 16, 0], // jaw
    [17, 21, 0], [22, 26, 0], // eyebrows
    [27, 30, 0], [31, 35, 0], // nose bridge, nose bottom
    [36, 41, 1], [42, 47, 1], // eyes
    [48, 59, 1], [60, 67, 1], // outer and inner lips
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (result.frames == 0) return;
    final f = frame.clamp(0, result.frames - 1);
    final scale = math.min(size.width / (_maxX - _minX), size.height / (_maxY - _minY));
    final dx = (size.width - (_maxX - _minX) * scale) / 2;
    final dy = (size.height - (_maxY - _minY) * scale) / 2;

    Offset? point(int joint) {
      final x = result.x(f, joint), y = result.y(f, joint);
      if (!x.isFinite || !y.isFinite || x.abs() > 4 || y.abs() > 4) return null; // outliers
      return Offset(dx + (x - _minX) * scale, dy + (y - _minY) * scale);
    }

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void bone(Paint paint, int a, int b) {
      final p = point(a), q = point(b);
      if (p != null && q != null) canvas.drawLine(p, q, paint);
    }

    final unit = scale / 100; // line widths scale with the canvas

    // --- Face ---
    final facePaint = stroke(faceColor, math.max(1.0, 1.4 * unit));
    for (final line in _faceLines) {
      final path = Path();
      var started = false;
      for (var i = line[0]; i <= line[1]; i++) {
        final p = point(_faceStart + i);
        if (p == null) continue;
        started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        started = true;
      }
      if (line[2] == 1 && started) path.close();
      canvas.drawPath(path, facePaint);
    }
    final pupilPaint = Paint()..color = faceColor;
    for (final i in [68, 69]) {
      final p = point(_faceStart + i);
      if (p != null) canvas.drawCircle(p, math.max(1.5, 2.0 * unit), pupilPaint);
    }

    // --- Body ---
    final bodyPaint = stroke(bodyColor, math.max(3.0, 6.0 * unit));
    for (final b in _bodyBones) {
      bone(bodyPaint, b[0], b[1]);
    }
    final jointPaint = Paint()..color = bodyColor;
    for (var i = 0; i < 11; i++) {
      final p = point(i);
      if (p != null) canvas.drawCircle(p, math.max(3.0, 5.0 * unit), jointPaint);
    }

    // --- Hands ---
    for (final (start, color) in [(_handA, handColorA), (_handB, handColorB)]) {
      if (!_handVisible(f, start)) continue;
      final handPaint = stroke(color, math.max(1.5, 2.6 * unit));
      for (final b in _handBones) {
        bone(handPaint, start + b[0], start + b[1]);
      }
      // Connect the hand to whichever arm wrist is closer.
      final wrist = point(start);
      if (wrist != null) {
        Offset? nearest;
        var best = double.infinity;
        for (final w in _bodyWrists) {
          final p = point(w);
          if (p == null) continue;
          final d = (p - wrist).distance;
          if (d < best) {
            best = d;
            nearest = p;
          }
        }
        if (nearest != null && best < 0.4 * scale) {
          canvas.drawLine(nearest, wrist, stroke(bodyColor, math.max(2.0, 4.0 * unit)));
        }
      }
      final dotPaint = Paint()..color = color;
      for (var i = 0; i < 21; i++) {
        final p = point(start + i);
        if (p != null) canvas.drawCircle(p, math.max(1.5, 2.4 * unit), dotPaint);
      }
    }
  }

  /// A hand whose points have collapsed onto one spot is treated as "not visible".
  bool _handVisible(int f, int start) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < 21; i++) {
      final x = result.x(f, start + i), y = result.y(f, start + i);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    return (maxX - minX) + (maxY - minY) > 0.02;
  }

  @override
  bool shouldRepaint(SignSkeletonPainter old) => old.frame != frame || old.result != result;
}
