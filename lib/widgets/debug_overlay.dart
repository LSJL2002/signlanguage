import 'package:flutter/material.dart';

class DebugOverlay extends StatelessWidget {
  final int faceLandmarkCount;
  final bool faceDots;
  final VoidCallback? onToggleFaceDots;
  final bool hasHand;
  final int landmarkCount;
  final double fps;
  final int fingerCount;

  const DebugOverlay({
    super.key,
    this.faceLandmarkCount = 0,
    this.faceDots = true,
    this.onToggleFaceDots,
    required this.hasHand,
    required this.landmarkCount,
    required this.fps,
    required this.fingerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(166),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Face: ${faceLandmarkCount > 0 ? 'YES' : 'NO'}',
            style: const TextStyle(color: Colors.limeAccent, fontSize: 12),
          ),
          Text(
            'Face landmarks: $faceLandmarkCount',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (onToggleFaceDots != null)
            GestureDetector(
              onTap: onToggleFaceDots,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  faceDots
                      ? 'Face: dots (tap for contours)'
                      : 'Face: contours (tap for dots)',
                  style: const TextStyle(
                    color: Colors.limeAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasHand ? Icons.check_circle : Icons.cancel,
                color: hasHand ? Colors.greenAccent : Colors.redAccent,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Hand: ${hasHand ? 'YES' : 'NO'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Landmarks: $landmarkCount',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'FPS: ${fps.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'Fingers: ${hasHand && fingerCount >= 0 ? fingerCount : '-'}',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
