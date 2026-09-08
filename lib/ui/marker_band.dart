import 'package:flutter/material.dart';

import 'theme.dart';

class MarkerBand extends StatelessWidget {
  const MarkerBand({
    super.key,
    required this.color,
    required this.height,
    required this.texture,
    this.capStart = false,
    this.capEnd = false,
  });

  final Color color;
  final double height;
  final MarkerTexture texture;
  final bool capStart;
  final bool capEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: MarkerBandPainter(
          color: color,
          texture: texture,
          capStart: capStart,
          capEnd: capEnd,
        ),
      ),
    );
  }
}

class MarkerBandPainter extends CustomPainter {
  const MarkerBandPainter({
    required this.color,
    required this.texture,
    this.capStart = false,
    this.capEnd = false,
  });

  final Color color;
  final MarkerTexture texture;
  final bool capStart;
  final bool capEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final radius = const Radius.circular(Dim.radiusBandCap);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: capStart ? radius : Radius.zero,
        bottomLeft: capStart ? radius : Radius.zero,
        topRight: capEnd ? radius : Radius.zero,
        bottomRight: capEnd ? radius : Radius.zero,
      ),
    );

    final paint = Paint()..color = color;
    final (mark, gap) = MarkerTextureMetrics.forTexture(texture, size.width);
    for (var left = 0.0; left < size.width; left += mark + gap) {
      canvas.drawRect(
        Rect.fromLTRB(left, 0, (left + mark).clamp(0, size.width), size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkerBandPainter oldDelegate) =>
      color != oldDelegate.color ||
      texture != oldDelegate.texture ||
      capStart != oldDelegate.capStart ||
      capEnd != oldDelegate.capEnd;
}
