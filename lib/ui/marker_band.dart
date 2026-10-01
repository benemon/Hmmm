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

class PeriodCapsule extends StatelessWidget {
  const PeriodCapsule({
    super.key,
    required this.color,
    required this.capStart,
    required this.capEnd,
  });

  final Color color;
  final bool capStart;
  final bool capEnd;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: PeriodCapsulePainter(
      color: color,
      capStart: capStart,
      capEnd: capEnd,
    ),
  );
}

class PeriodCapsulePainter extends CustomPainter {
  const PeriodCapsulePainter({
    required this.color,
    required this.capStart,
    required this.capEnd,
  });

  final Color color;
  final bool capStart;
  final bool capEnd;

  @override
  void paint(Canvas canvas, Size size) {
    // Joined edges overlap the neighbouring day by half a pixel so
    // fractional cell widths do not anti-alias into a visible seam.
    final left = capStart ? size.width / 2 - Dim.periodCapsuleHeight / 2 : -0.5;
    final right = capEnd
        ? size.width / 2 + Dim.periodCapsuleHeight / 2
        : size.width + 0.5;
    final radius = const Radius.circular(Dim.periodCapsuleHeight / 2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(left, 0, right, size.height),
        topLeft: capStart ? radius : Radius.zero,
        bottomLeft: capStart ? radius : Radius.zero,
        topRight: capEnd ? radius : Radius.zero,
        bottomRight: capEnd ? radius : Radius.zero,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(PeriodCapsulePainter oldDelegate) =>
      color != oldDelegate.color ||
      capStart != oldDelegate.capStart ||
      capEnd != oldDelegate.capEnd;
}

class CourseBand extends StatelessWidget {
  const CourseBand({
    super.key,
    required this.color,
    required this.texture,
    required this.capStart,
    required this.capEnd,
    this.name,
  });

  final Color color;
  final MarkerTexture texture;
  final bool capStart;
  final bool capEnd;
  final String? name;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: CourseBandPainter(
      color: color,
      texture: texture,
      capStart: capStart,
      capEnd: capEnd,
      fillOpacity: Theme.of(context).brightness == Brightness.light
          ? 0.16
          : 0.22,
    ),
    child: name == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                name!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
  );
}

class CourseBandPainter extends CustomPainter {
  const CourseBandPainter({
    required this.color,
    required this.texture,
    required this.capStart,
    required this.capEnd,
    required this.fillOpacity,
  });

  final Color color;
  final MarkerTexture texture;
  final bool capStart;
  final bool capEnd;
  final double fillOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const strokeWidth = 1.5;
    final inset = strokeWidth / 2;
    final radius = size.height / 2 - inset;
    final capRadius = Radius.circular(radius);
    final rect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final fill = RRect.fromRectAndCorners(
      rect,
      topLeft: capStart ? capRadius : Radius.zero,
      bottomLeft: capStart ? capRadius : Radius.zero,
      topRight: capEnd ? capRadius : Radius.zero,
      bottomRight: capEnd ? capRadius : Radius.zero,
    );
    canvas.drawRRect(
      fill,
      Paint()..color = color.withValues(alpha: fillOpacity),
    );

    final path = Path()..moveTo(capStart ? radius + inset : 0, inset);
    path.lineTo(capEnd ? size.width - radius - inset : size.width, inset);
    if (capEnd) {
      path.arcToPoint(
        Offset(size.width - radius - inset, size.height - inset),
        radius: capRadius,
        clockwise: true,
      );
    } else {
      path.moveTo(size.width, size.height - inset);
    }
    path.lineTo(capStart ? radius + inset : 0, size.height - inset);
    if (capStart) {
      path.arcToPoint(
        Offset(radius + inset, inset),
        radius: capRadius,
        clockwise: true,
      );
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = texture == MarkerTexture.dotted
          ? StrokeCap.round
          : StrokeCap.butt;
    if (texture == MarkerTexture.solid) {
      canvas.drawPath(path, paint);
      return;
    }
    final (mark, gap) = MarkerTextureMetrics.forTexture(texture, size.width);
    for (final metric in path.computeMetrics()) {
      for (
        var distance = 0.0;
        distance < metric.length;
        distance += mark + gap
      ) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + mark).clamp(0, metric.length),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CourseBandPainter oldDelegate) =>
      color != oldDelegate.color ||
      texture != oldDelegate.texture ||
      capStart != oldDelegate.capStart ||
      capEnd != oldDelegate.capEnd ||
      fillOpacity != oldDelegate.fillOpacity;
}

class TodayRing extends StatelessWidget {
  const TodayRing({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: TodayRingPainter(color));
}

class TodayRingPainter extends CustomPainter {
  const TodayRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addOval(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2));
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 4) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 2).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TodayRingPainter oldDelegate) =>
      color != oldDelegate.color;
}
