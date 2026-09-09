import 'package:flutter/material.dart';

const _sans = 'Public Sans';
const _mono = 'DM Mono';

enum MarkerTexture { solid, dotted, dashed, fineDot }

abstract final class MarkerTextureMetrics {
  static const dottedMark = 3.0;
  static const dottedGap = 3.0;
  static const dashedMark = 8.0;
  static const dashedGap = 4.0;
  static const fineDotMark = 2.0;
  static const fineDotGap = 3.0;

  static (double, double) forTexture(
    MarkerTexture texture,
    double solidWidth,
  ) => switch (texture) {
    MarkerTexture.solid => (solidWidth, 0),
    MarkerTexture.dotted => (dottedMark, dottedGap),
    MarkerTexture.dashed => (dashedMark, dashedGap),
    MarkerTexture.fineDot => (fineDotMark, fineDotGap),
  };
}

class MarkerLane {
  const MarkerLane({
    required this.color,
    required this.texture,
    required this.label,
  });

  final Color color;
  final MarkerTexture texture;
  final String label;
}

/// Marker lane identity is position + texture + L-label, before hue. The
/// contrast-first L1/L3 palette converges under CVD and sits below normal-
/// vision hue separation, so textures are load-bearing and may never be
/// dropped.
class Markers extends ThemeExtension<Markers> {
  const Markers({
    required this.period,
    required this.lanes,
    required this.overflow,
  });

  final Color period;
  final List<MarkerLane> lanes;
  final MarkerLane overflow;

  MarkerLane lane(int index) =>
      index >= 0 && index < lanes.length ? lanes[index] : overflow;

  static const light = Markers(
    period: Color(0xFFB4243C),
    lanes: [
      MarkerLane(
        color: Color(0xFF1E5AA8),
        texture: MarkerTexture.solid,
        label: 'L1',
      ),
      MarkerLane(
        color: Color(0xFF8A5A00),
        texture: MarkerTexture.dotted,
        label: 'L2',
      ),
      MarkerLane(
        color: Color(0xFF6B3FA0),
        texture: MarkerTexture.dashed,
        label: 'L3',
      ),
    ],
    overflow: MarkerLane(
      color: Color(0xFF55534A),
      texture: MarkerTexture.fineDot,
      label: 'L4+',
    ),
  );

  static const dark = Markers(
    period: Color(0xFFF2707E),
    lanes: [
      MarkerLane(
        color: Color(0xFF7FB2F0),
        texture: MarkerTexture.solid,
        label: 'L1',
      ),
      MarkerLane(
        color: Color(0xFFE0A63C),
        texture: MarkerTexture.dotted,
        label: 'L2',
      ),
      MarkerLane(
        color: Color(0xFFC29BF2),
        texture: MarkerTexture.dashed,
        label: 'L3',
      ),
    ],
    overflow: MarkerLane(
      color: Color(0xFFB3B1A4),
      texture: MarkerTexture.fineDot,
      label: 'L4+',
    ),
  );

  static const print = Markers(
    period: Color(0xFF000000),
    lanes: [
      MarkerLane(
        color: Color(0xFF000000),
        texture: MarkerTexture.solid,
        label: 'L1',
      ),
      MarkerLane(
        color: Color(0xFF000000),
        texture: MarkerTexture.dotted,
        label: 'L2',
      ),
      MarkerLane(
        color: Color(0xFF000000),
        texture: MarkerTexture.dashed,
        label: 'L3',
      ),
    ],
    overflow: MarkerLane(
      color: Color(0xFF000000),
      texture: MarkerTexture.fineDot,
      label: 'L4+',
    ),
  );

  static Markers of(BuildContext context) =>
      Theme.of(context).extension<Markers>()!;

  @override
  Markers copyWith({
    Color? period,
    List<MarkerLane>? lanes,
    MarkerLane? overflow,
  }) {
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
        for (var index = 0; index < lanes.length; index++)
          MarkerLane(
            color: Color.lerp(lanes[index].color, other.lane(index).color, t)!,
            texture: other.lane(index).texture,
            label: other.lane(index).label,
          ),
      ],
      overflow: MarkerLane(
        color: Color.lerp(overflow.color, other.overflow.color, t)!,
        texture: other.overflow.texture,
        label: other.overflow.label,
      ),
    );
  }
}

class HmmmType extends ThemeExtension<HmmmType> {
  const HmmmType({
    required this.figure,
    required this.figureSmall,
    required this.dayNumber,
    required this.bodyStrong,
  });

  final TextStyle figure;
  final TextStyle figureSmall;
  final TextStyle dayNumber;
  final TextStyle bodyStrong;

  static HmmmType of(BuildContext context) =>
      Theme.of(context).extension<HmmmType>()!;

  @override
  HmmmType copyWith({
    TextStyle? figure,
    TextStyle? figureSmall,
    TextStyle? dayNumber,
    TextStyle? bodyStrong,
  }) {
    return HmmmType(
      figure: figure ?? this.figure,
      figureSmall: figureSmall ?? this.figureSmall,
      dayNumber: dayNumber ?? this.dayNumber,
      bodyStrong: bodyStrong ?? this.bodyStrong,
    );
  }

  @override
  HmmmType lerp(HmmmType? other, double t) {
    if (other == null) return this;
    return HmmmType(
      figure: TextStyle.lerp(figure, other.figure, t)!,
      figureSmall: TextStyle.lerp(figureSmall, other.figureSmall, t)!,
      dayNumber: TextStyle.lerp(dayNumber, other.dayNumber, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
    );
  }
}

abstract final class Dim {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;

  static const radiusBandCap = 2.0;
  static const radiusToday = 4.0;
  static const radiusControl = 8.0;
  static const radiusSheet = 16.0;
  static const radiusDialog = 20.0;

  static const minTarget = 48.0;
  static const rowMinHeight = 56.0;
  static const tableRowMinHeight = 44.0;

  static const legendHeight = 40.0;
  static const weekdayRowHeight = 24.0;
  static const monthBandHeight = 32.0;
  static const navBarHeight = 80.0;
  static const daySheetHeaderHeight = 64.0;

  static const periodBandHeight = 6.0;
  static const laneBandHeight = 4.0;
  static const lanePitch = 6.0;
  static const glyphSizeCalendar = 10.0;
  static const glyphSizeTable = 12.0;
  static const glyphSizeChip = 14.0;
  static const glyphSizeList = 16.0;

  static double dayCellHeight(int laneCount) => 54 + lanePitch * laneCount;

  static double monthExtent(int laneCount) =>
      monthBandHeight + 6 * dayCellHeight(laneCount);

  static const agendaModeTextScale = 1.3;
  static const singleColumnTextScale = 1.4;

  // Keep in sync with visibleDayCellSymptomLimit in domain/calendar.dart.
  static const visibleGlyphLimit = 3;
}

abstract final class Motion {
  static const state = Duration(milliseconds: 120);
  static const dayPage = Duration(milliseconds: 180);
  static const sheet = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  static Duration scaled(BuildContext context, Duration base) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : base;
}

ThemeData hmmmTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final surface = isLight ? const Color(0xFFFBFAF7) : const Color(0xFF131311);
  final surfaceRaised = isLight
      ? const Color(0xFFF4F2EC)
      : const Color(0xFF1C1C19);
  final ink = isLight ? const Color(0xFF16150F) : const Color(0xFFF5F4EE);
  final inkMuted = isLight ? const Color(0xFF55534A) : const Color(0xFFB3B1A4);
  final border = isLight ? const Color(0xFF8A8779) : const Color(0xFF6E6C61);
  final rule = isLight ? const Color(0xFFDEDBD0) : const Color(0xFF2B2A26);
  final action = isLight ? const Color(0xFF5B3492) : const Color(0xFFC29BF2);
  final onAction = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A0B33);
  final inverseSurface = isLight
      ? const Color(0xFF2E2C22)
      : const Color(0xFFE8E6DC);
  final onInverseSurface = isLight
      ? const Color(0xFFF5F4EE)
      : const Color(0xFF1C1C19);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: action,
    onPrimary: onAction,
    primaryContainer: action,
    onPrimaryContainer: onAction,
    secondary: action,
    onSecondary: onAction,
    surface: surface,
    onSurface: ink,
    surfaceContainerHighest: surfaceRaised,
    onSurfaceVariant: inkMuted,
    outline: border,
    outlineVariant: rule,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    error: isLight ? const Color(0xFFB4243C) : const Color(0xFFF2707E),
    onError: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF33070F),
  );

  final text = TextTheme(
    headlineSmall: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w600,
      fontSize: 24,
      height: 30 / 24,
      letterSpacing: -0.24,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w500,
      fontSize: 22,
      height: 28 / 22,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w600,
      fontSize: 19,
      height: 26 / 19,
      color: ink,
    ),
    bodyLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      height: 22 / 15,
      color: ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      height: 18 / 13,
      color: inkMuted,
    ),
    labelSmall: TextStyle(
      fontFamily: _mono,
      fontWeight: FontWeight.w500,
      fontSize: 11,
      height: 16 / 11,
      letterSpacing: 1.32,
      color: ink,
    ),
    labelLarge: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w500,
      fontSize: 15,
      height: 22 / 15,
    ),
  );
  final hmmmType = HmmmType(
    figure: TextStyle(
      fontFamily: _mono,
      fontSize: 15,
      height: 22 / 15,
      color: ink,
    ),
    figureSmall: TextStyle(
      fontFamily: _mono,
      fontSize: 13,
      height: 18 / 13,
      color: ink,
    ),
    dayNumber: TextStyle(
      fontFamily: _mono,
      fontWeight: FontWeight.w500,
      fontSize: 13,
      height: 16 / 13,
      color: ink,
    ),
    bodyStrong: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w600,
      fontSize: 15,
      height: 22 / 15,
      color: ink,
    ),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    fontFamily: _sans,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: action,
        foregroundColor: onAction,
        minimumSize: const Size(0, Dim.minTarget),
        padding: const EdgeInsets.symmetric(horizontal: Dim.s5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Dim.radiusControl)),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: border),
        minimumSize: const Size(0, Dim.minTarget),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Dim.radiusControl)),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: action,
        minimumSize: const Size(0, Dim.minTarget),
        padding: const EdgeInsets.symmetric(horizontal: Dim.s3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Dim.radiusControl)),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      isDense: false,
      constraints: const BoxConstraints(minHeight: Dim.minTarget),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Dim.s3,
        vertical: Dim.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(Dim.radiusControl),
        ),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(Dim.radiusControl),
        ),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(Dim.radiusControl),
        ),
        borderSide: BorderSide(color: ink, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Dim.radiusDialog)),
        side: BorderSide(color: border),
      ),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: isLight ? 0.40 : 0.55),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Dim.radiusSheet),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(Dim.radiusControl),
        ),
        side: BorderSide(color: border),
      ),
      textStyle: text.bodyLarge,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dim.radiusControl),
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: inverseSurface,
      contentTextStyle: TextStyle(
        fontFamily: _sans,
        fontSize: 14,
        height: 20 / 14,
        color: onInverseSurface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Dim.radiusControl)),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: Dim.navBarHeight,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? ink : inkMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelSmall!.copyWith(
          color: states.contains(WidgetState.selected) ? ink : inkMuted,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? action : Colors.transparent,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? action : border,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? onAction : inkMuted,
      ),
    ),
    extensions: [isLight ? Markers.light : Markers.dark, hmmmType],
  );
}
