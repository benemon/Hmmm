import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/ui/theme.dart';

void main() {
  test('band palette meets contrast and separation thresholds', () {
    final lightTheme = hmmmTheme(Brightness.light);
    final darkTheme = hmmmTheme(Brightness.dark);
    final lightMarkers = lightTheme.extension<Markers>()!;
    final darkMarkers = darkTheme.extension<Markers>()!;

    expect(
      [for (final swatch in bandColourSwatches) swatch.id],
      ['red', 'blue', 'amber', 'purple', 'teal', 'green', 'magenta', 'slate'],
    );
    for (final swatch in bandColourSwatches) {
      expect(
        _contrast(swatch.light, lightTheme.colorScheme.surface),
        greaterThanOrEqualTo(3),
        reason: '${swatch.id} light against surface',
      );
      expect(
        _contrast(swatch.dark, darkTheme.colorScheme.surface),
        greaterThanOrEqualTo(3),
        reason: '${swatch.id} dark against surface',
      );
      expect(
        _contrast(swatch.light, lightMarkers.inkOnBand),
        greaterThanOrEqualTo(4.5),
        reason: 'light ink on ${swatch.id}',
      );
      expect(
        _contrast(swatch.dark, darkMarkers.inkOnBand),
        greaterThanOrEqualTo(4.5),
        reason: 'dark ink on ${swatch.id}',
      );
    }

    for (var first = 0; first < bandColourSwatches.length; first++) {
      for (
        var second = first + 1;
        second < bandColourSwatches.length;
        second++
      ) {
        final a = bandColourSwatches[first];
        final b = bandColourSwatches[second];
        expect(
          _oklabDistance(a.light, b.light),
          greaterThanOrEqualTo(0.08),
          reason: '${a.id}/${b.id} light',
        );
        expect(
          _oklabDistance(a.dark, b.dark),
          greaterThanOrEqualTo(0.08),
          reason: '${a.id}/${b.id} dark',
        );
      }
    }
  });
}

double _contrast(Color first, Color second) {
  final lighter = math.max(first.computeLuminance(), second.computeLuminance());
  final darker = math.min(first.computeLuminance(), second.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}

double _oklabDistance(Color first, Color second) {
  final a = _oklab(first);
  final b = _oklab(second);
  return math.sqrt(
    math.pow(a.$1 - b.$1, 2) +
        math.pow(a.$2 - b.$2, 2) +
        math.pow(a.$3 - b.$3, 2),
  );
}

(double, double, double) _oklab(Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  final red = linear(color.r);
  final green = linear(color.g);
  final blue = linear(color.b);
  final l = math
      .pow(
        0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue,
        1 / 3,
      )
      .toDouble();
  final m = math
      .pow(
        0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue,
        1 / 3,
      )
      .toDouble();
  final s = math
      .pow(
        0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue,
        1 / 3,
      )
      .toDouble();
  return (
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  );
}
