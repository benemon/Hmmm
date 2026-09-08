import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/ui/marker_band.dart';
import 'package:hmmm/ui/theme.dart';

void main() {
  test('lane indices beyond configured lanes use the overflow marker', () {
    expect(
      Markers.light.lane(Markers.light.lanes.length),
      same(Markers.light.overflow),
    );
  });

  Future<int Function(int x, int y)> alphaSampler(
    MarkerTexture texture,
    Size size,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    MarkerBandPainter(
      color: Colors.black,
      texture: texture,
    ).paint(canvas, size);
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return (x, y) => bytes!.getUint8((y * size.width.toInt() + x) * 4 + 3);
  }

  test('dashed marker painter leaves transparent gaps', () async {
    final alphaAt = await alphaSampler(MarkerTexture.dashed, const Size(24, 4));
    expect(alphaAt(2, 2), 255);
    expect(alphaAt(9, 2), 0);
    expect(alphaAt(14, 2), 255);
  });

  test('dotted rhythm is 3 on, 3 off', () async {
    final alphaAt = await alphaSampler(MarkerTexture.dotted, const Size(24, 4));
    expect(alphaAt(1, 2), 255);
    expect(alphaAt(4, 2), 0);
    expect(alphaAt(7, 2), 255);
    expect(alphaAt(10, 2), 0);
  });

  test('fine-dot rhythm is 2 on, 3 off and distinct from dotted', () async {
    final alphaAt = await alphaSampler(
      MarkerTexture.fineDot,
      const Size(24, 4),
    );
    expect(alphaAt(1, 2), 255);
    expect(alphaAt(3, 2), 0);
    expect(alphaAt(6, 2), 255);
    expect(alphaAt(9, 2), 0);
  });

  test('solid paints the full width', () async {
    final alphaAt = await alphaSampler(MarkerTexture.solid, const Size(24, 4));
    for (final x in [0, 6, 12, 18, 23]) {
      expect(alphaAt(x, 2), 255);
    }
  });
}
