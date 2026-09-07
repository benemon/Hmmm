import 'package:flutter/material.dart';

/// Marker colours for calendar bands and trends. The green lane sits below
/// 3:1 contrast on the light surface (2.74:1), so hue never carries identity
/// alone: medication lanes are positional (fixed by ascending medication id)
/// and a legend stays visible wherever markers render. No fourth hue passes
/// the dark-mode colour-vision floors.
class Markers extends ThemeExtension<Markers> {
  const Markers({
    required this.period,
    required this.lanes,
    required this.overflow,
  });

  final Color period;
  final List<Color> lanes;
  final Color overflow;

  Color lane(int index) => index < lanes.length ? lanes[index] : overflow;

  static const light = Markers(
    period: Color(0xFFE34948),
    lanes: [Color(0xFF2A78D6), Color(0xFF1BAF7A)],
    overflow: Color(0xFF898781),
  );

  static const dark = Markers(
    period: Color(0xFFE66767),
    lanes: [Color(0xFF3987E5), Color(0xFF199E70)],
    overflow: Color(0xFF898781),
  );

  static Markers of(BuildContext context) =>
      Theme.of(context).extension<Markers>()!;

  @override
  Markers copyWith({Color? period, List<Color>? lanes, Color? overflow}) {
    return Markers(
      period: period ?? this.period,
      lanes: lanes ?? this.lanes,
      overflow: overflow ?? this.overflow,
    );
  }

  @override
  Markers lerp(Markers? other, double t) {
    if (other == null) return this;
    return Markers(
      period: Color.lerp(period, other.period, t)!,
      lanes: [
        for (var i = 0; i < lanes.length; i++)
          Color.lerp(lanes[i], other.lane(i), t)!,
      ],
      overflow: Color.lerp(overflow, other.overflow, t)!,
    );
  }
}

/// Symptom identity is carried by shape in primary ink, never by colour.
/// Assignment is stable per symptom type id; the ten builtin types seeded by
/// the data layer each get a distinct glyph.
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

/// Merge into any style for columns of figures that must align vertically.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

ThemeData hmmmTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final surface = light ? const Color(0xFFFCFCFB) : const Color(0xFF1A1A19);
  final ink = light ? const Color(0xFF0B0B0B) : const Color(0xFFFFFFFF);
  final inkSecondary = light
      ? const Color(0xFF52514E)
      : const Color(0xFFC3C2B7);
  final hairline = light ? const Color(0xFFE1E0D9) : const Color(0xFF2C2C2A);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF52514E),
        brightness: brightness,
      ).copyWith(
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: inkSecondary,
        outlineVariant: hairline,
      );

  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    extensions: [light ? Markers.light : Markers.dark],
  );
}
