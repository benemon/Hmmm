import 'dart:math' as math;

import 'package:flutter/material.dart';

enum SymptomGlyph {
  circle,
  diamond,
  triangle,
  square,
  plus,
  circleOpen,
  diamondOpen,
  triangleOpen,
  squareOpen,
  cross;

  static SymptomGlyph forTypeId(int symptomTypeId) =>
      values[(symptomTypeId - 1) % values.length];
}

class SymptomGlyphMark extends StatelessWidget {
  const SymptomGlyphMark({super.key, required this.typeId, required this.size});

  final int typeId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SymptomGlyphPainter(
        SymptomGlyph.forTypeId(typeId),
        Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _SymptomGlyphPainter extends CustomPainter {
  const _SymptomGlyphPainter(this.glyph, this.color);

  final SymptomGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.5, size.shortestSide / 8)
      ..strokeCap = StrokeCap.square;
    final center = size.center(Offset.zero);
    final inset = paint.strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - paint.strokeWidth,
      size.height - paint.strokeWidth,
    );
    final path = Path();

    switch (glyph) {
      case SymptomGlyph.circle:
      case SymptomGlyph.circleOpen:
        paint.style = glyph == SymptomGlyph.circle
            ? PaintingStyle.fill
            : PaintingStyle.stroke;
        canvas.drawOval(rect, paint);
      case SymptomGlyph.diamond:
      case SymptomGlyph.diamondOpen:
        path
          ..moveTo(center.dx, inset)
          ..lineTo(size.width - inset, center.dy)
          ..lineTo(center.dx, size.height - inset)
          ..lineTo(inset, center.dy)
          ..close();
        paint.style = glyph == SymptomGlyph.diamond
            ? PaintingStyle.fill
            : PaintingStyle.stroke;
        canvas.drawPath(path, paint);
      case SymptomGlyph.triangle:
      case SymptomGlyph.triangleOpen:
        path
          ..moveTo(center.dx, inset)
          ..lineTo(size.width - inset, size.height - inset)
          ..lineTo(inset, size.height - inset)
          ..close();
        paint.style = glyph == SymptomGlyph.triangle
            ? PaintingStyle.fill
            : PaintingStyle.stroke;
        canvas.drawPath(path, paint);
      case SymptomGlyph.square:
      case SymptomGlyph.squareOpen:
        paint.style = glyph == SymptomGlyph.square
            ? PaintingStyle.fill
            : PaintingStyle.stroke;
        canvas.drawRect(rect, paint);
      case SymptomGlyph.plus:
        paint.style = PaintingStyle.stroke;
        canvas
          ..drawLine(
            Offset(center.dx, inset),
            Offset(center.dx, size.height - inset),
            paint,
          )
          ..drawLine(
            Offset(inset, center.dy),
            Offset(size.width - inset, center.dy),
            paint,
          );
      case SymptomGlyph.cross:
        paint.style = PaintingStyle.stroke;
        canvas
          ..drawLine(
            Offset(inset, inset),
            Offset(size.width - inset, size.height - inset),
            paint,
          )
          ..drawLine(
            Offset(size.width - inset, inset),
            Offset(inset, size.height - inset),
            paint,
          );
    }
  }

  @override
  bool shouldRepaint(_SymptomGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
