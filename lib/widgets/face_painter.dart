import 'package:flutter/material.dart';

import '../services/pose_service.dart';

/// Sparse MediaPipe semantic contours, not tessellation or iris meshes.
/// Connection data: Google MediaPipe face_mesh_connections.py (Apache-2.0).
/// https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/python/solutions/face_mesh_connections.py
class FacePainter extends CustomPainter {
  const FacePainter(this.landmarks, {this.debugPoints = false});
  final bool debugPoints;
  final List<Landmark> landmarks;
  static const connections = <List<int>>[
    [61, 146],
    [146, 91],
    [91, 181],
    [181, 84],
    [84, 17],
    [17, 314],
    [314, 405],
    [405, 321],
    [321, 375],
    [375, 291],
    [61, 185],
    [185, 40],
    [40, 39],
    [39, 37],
    [37, 0],
    [0, 267],
    [267, 269],
    [269, 270],
    [270, 409],
    [409, 291],
    [78, 95],
    [95, 88],
    [88, 178],
    [178, 87],
    [87, 14],
    [14, 317],
    [317, 402],
    [402, 318],
    [318, 324],
    [324, 308],
    [78, 191],
    [191, 80],
    [80, 81],
    [81, 82],
    [82, 13],
    [13, 312],
    [312, 311],
    [311, 310],
    [310, 415],
    [415, 308],
    [263, 249],
    [249, 390],
    [390, 373],
    [373, 374],
    [374, 380],
    [380, 381],
    [381, 382],
    [382, 362],
    [263, 466],
    [466, 388],
    [388, 387],
    [387, 386],
    [386, 385],
    [385, 384],
    [384, 398],
    [398, 362],
    [276, 283],
    [283, 282],
    [282, 295],
    [295, 285],
    [300, 293],
    [293, 334],
    [334, 296],
    [296, 336],
    [33, 7],
    [7, 163],
    [163, 144],
    [144, 145],
    [145, 153],
    [153, 154],
    [154, 155],
    [155, 133],
    [33, 246],
    [246, 161],
    [161, 160],
    [160, 159],
    [159, 158],
    [158, 157],
    [157, 173],
    [173, 133],
    [46, 53],
    [53, 52],
    [52, 65],
    [65, 55],
    [70, 63],
    [63, 105],
    [105, 66],
    [66, 107],
    [10, 338],
    [338, 297],
    [297, 332],
    [332, 284],
    [284, 251],
    [251, 389],
    [389, 356],
    [356, 454],
    [454, 323],
    [323, 361],
    [361, 288],
    [288, 397],
    [397, 365],
    [365, 379],
    [379, 378],
    [378, 400],
    [400, 377],
    [377, 152],
    [152, 148],
    [148, 176],
    [176, 149],
    [149, 150],
    [150, 136],
    [136, 172],
    [172, 58],
    [58, 132],
    [132, 93],
    [93, 234],
    [234, 127],
    [127, 162],
    [162, 21],
    [21, 54],
    [54, 103],
    [103, 67],
    [67, 109],
    [109, 10],
    [168, 6],
    [6, 197],
    [197, 195],
    [195, 5],
    [5, 4],
    [4, 1],
    [1, 19],
    [19, 94],
    [94, 2],
    [98, 97],
    [97, 2],
    [2, 326],
    [326, 327],
    [327, 294],
    [294, 278],
    [278, 344],
    [344, 440],
    [440, 275],
    [275, 4],
    [4, 45],
    [45, 220],
    [220, 115],
    [115, 48],
    [48, 64],
    [64, 98],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFFD5F5E8)
      ..strokeWidth = 1.2;
    bool valid(Landmark p) =>
        (p['x'] ?? double.nan).isFinite && (p['y'] ?? double.nan).isFinite;
    Offset at(Landmark p) =>
        Offset(p['x']! * size.width, p['y']! * size.height);
    final inBounds = landmarks
        .where((p) => valid(p) && (Offset.zero & size).contains(at(p)))
        .length;
    debugPrint(
      'KSL_PAINT face points count=${landmarks.length} inBounds=$inBounds canvas=$size dots=$debugPoints',
    );
    if (landmarks.isNotEmpty && valid(landmarks.first)) {
      debugPrint(
        'KSL_COORD normalized=${landmarks.first} -> canvas=${at(landmarks.first)} inBounds=${(Offset.zero & size).contains(at(landmarks.first))} (preview applies shared cover-fit)',
      );
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (debugPoints) {
      final dot = Paint()..color = Colors.limeAccent;
      for (final point in landmarks) {
        if (valid(point)) canvas.drawCircle(at(point), 2, dot);
      }
    }
    for (final edge in debugPoints ? <List<int>>[] : connections) {
      if (edge[0] >= landmarks.length || edge[1] >= landmarks.length) continue;
      final a = landmarks[edge[0]], b = landmarks[edge[1]];
      if (valid(a) && valid(b)) canvas.drawLine(at(a), at(b), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) =>
      oldDelegate.landmarks != landmarks ||
      oldDelegate.debugPoints != debugPoints;
}
