import 'package:flutter/material.dart';

import '../services/pose_service.dart';
import 'landmark_painter.dart';
import 'face_painter.dart';

class PosePainter extends CustomPainter {
  const PosePainter(this.landmarks, {this.leftWrist, this.rightWrist});
  final Landmark? leftWrist;
  final Landmark? rightWrist;
  static const excludedHandPoints = {17, 18, 19, 20, 21, 22};
  final List<Map<String, double>> landmarks;

  static const connections = [
    [11, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
    [11, 23],
    [12, 24],
    [23, 24],
    [23, 25],
    [24, 26],
    [25, 27],
    [26, 28],
    [27, 29],
    [28, 30],
    [29, 31],
    [30, 32],
    [27, 31],
    [28, 32],
  ];

  static bool visible(Map<String, double> p) =>
      (p['visibility'] ?? 0) >= .5 &&
      (p['presence'] ?? 0) >= .5 &&
      (p['x'] ?? double.nan).isFinite &&
      (p['y'] ?? double.nan).isFinite;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2;
    final dot = Paint()..color = Colors.cyanAccent;
    // Keep elbow endpoints in Pose's own skeleton: 13→15 and 14→16.
    // Hand wrists only suppress duplicate dots; they must not replace Pose endpoints.
    Landmark pointAt(int index) => landmarks[index];
    bool drawable(int index) {
      final p = pointAt(index);
      const threshold = .5;
      return (p['visibility'] ?? 0) >= threshold &&
          (p['presence'] ?? 0) >= threshold &&
          (p['x'] ?? double.nan).isFinite &&
          (p['y'] ?? double.nan).isFinite;
    }

    Offset position(Map<String, double> p) =>
        Offset(p['x']! * size.width, p['y']! * size.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final edge in connections) {
      if (edge[0] >= landmarks.length || edge[1] >= landmarks.length) continue;
      final a = pointAt(edge[0]), b = pointAt(edge[1]);
      if (drawable(edge[0]) && drawable(edge[1])) {
        canvas.drawLine(position(a), position(b), line);
      }
    }
    for (var index = 11; index < landmarks.length; index++) {
      if (excludedHandPoints.contains(index) ||
          (index == 15 && leftWrist != null) ||
          (index == 16 && rightWrist != null)) {
        continue;
      }
      if (drawable(index)) {
        canvas.drawCircle(position(pointAt(index)), 3, dot);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) =>
      oldDelegate.landmarks != landmarks ||
      oldDelegate.leftWrist != leftWrist ||
      oldDelegate.rightWrist != rightWrist;
}

/// All groups already share upright, preview-mirrored normalized coordinates.
class TrackingPainter extends CustomPainter {
  const TrackingPainter(this.frame, {this.debugFacePoints = false});
  final bool debugFacePoints;
  final TrackingFrame? frame;
  @override
  void paint(Canvas canvas, Size size) {
    final data = frame;
    if (data == null) return;
    Landmark? wrist(TrackedHand? hand) {
      if (hand == null || hand.confidence < .6 || hand.landmarks.length != 21) {
        return null;
      }
      final p = hand.landmarks.first;
      return (p['x'] ?? double.nan).isFinite && (p['y'] ?? double.nan).isFinite
          ? p
          : null;
    }

    PosePainter(
      data.body,
      leftWrist: wrist(data.leftHand),
      rightWrist: wrist(data.rightHand),
    ).paint(canvas, size);
    FacePainter(data.face, debugPoints: debugFacePoints).paint(canvas, size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    void drawHand(TrackedHand? hand, Color color) {
      if (hand == null || hand.confidence < .6) return;
      final points = hand.landmarks;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2;
      bool valid(Landmark p) =>
          (p['x'] ?? double.nan).isFinite && (p['y'] ?? double.nan).isFinite;
      Offset at(Landmark p) =>
          Offset(p['x']! * size.width, p['y']! * size.height);
      for (final edge in LandmarkPainter.connections) {
        final a = points[edge[0]], b = points[edge[1]];
        if (valid(a) && valid(b)) canvas.drawLine(at(a), at(b), paint);
      }
      for (final p in points) {
        if (valid(p)) canvas.drawCircle(at(p), 3, paint);
      }
    }

    drawHand(data.leftHand, Colors.amberAccent);
    drawHand(data.rightHand, Colors.pinkAccent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TrackingPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.debugFacePoints != debugFacePoints;
}
