import 'package:material_ui/material_ui.dart';

/// Apple-style UI tokens and semantic status colors via `Theme.of(context).extension<CloudPocketColors>()`.
@immutable
class CloudPocketColors extends ThemeExtension<CloudPocketColors> {
  // Semantic status colors
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;
  final Color info;
  final Color onInfo;

  // Apple Design Tokens from /design/cloudpocket.html
  final Color bg;
  final Color card;
  final Color label;
  final Color label2;
  final Color sep;
  final Color fill;
  final Color thumb;
  final Color glass;
  final Color blue;
  final Color green;
  final Color red;
  final Color orange;
  final List<BoxShadow> shadow;

  const CloudPocketColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.onInfo,
    required this.bg,
    required this.card,
    required this.label,
    required this.label2,
    required this.sep,
    required this.fill,
    required this.thumb,
    required this.glass,
    required this.blue,
    required this.green,
    required this.red,
    required this.orange,
    required this.shadow,
  });

  static const light = CloudPocketColors(
    success: Color(0xFF34C759),
    onSuccess: Colors.white,
    warning: Color(0xFFFF9500),
    onWarning: Colors.white,
    danger: Color(0xFFFF3B30),
    onDanger: Colors.white,
    info: Color(0xFF007AFF),
    onInfo: Colors.white,
    bg: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    label2: Color(0xFF6C6C70),
    sep: Color.fromRGBO(60, 60, 67, 0.18),
    fill: Color.fromRGBO(120, 120, 128, 0.12),
    thumb: Color(0xFFFFFFFF),
    glass: Color.fromRGBO(250, 250, 252, 0.74),
    blue: Color(0xFF007AFF),
    green: Color(0xFF34C759),
    red: Color(0xFFFF3B30),
    orange: Color(0xFFFF9500),
    shadow: [
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.06), blurRadius: 30, offset: Offset(0, 10)),
    ],
  );

  static const dark = CloudPocketColors(
    success: Color(0xFF30D158),
    onSuccess: Color(0xFF052E16),
    warning: Color(0xFFFF9F0A),
    onWarning: Color(0xFF451A03),
    danger: Color(0xFFFF453A),
    onDanger: Color(0xFF450A0A),
    info: Color(0xFF0A84FF),
    onInfo: Color(0xFF083344),
    bg: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    label: Color(0xFFFFFFFF),
    label2: Color(0xFF9A9AA1),
    sep: Color.fromRGBO(84, 84, 88, 0.55),
    fill: Color.fromRGBO(120, 120, 128, 0.24),
    thumb: Color(0xFF636366),
    glass: Color.fromRGBO(28, 28, 30, 0.72),
    blue: Color(0xFF0A84FF),
    green: Color(0xFF30D158),
    red: Color(0xFFFF453A),
    orange: Color(0xFFFF9F0A),
    shadow: [
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 30, offset: Offset(0, 10)),
    ],
  );

  @override
  CloudPocketColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? onInfo,
    Color? bg,
    Color? card,
    Color? label,
    Color? label2,
    Color? sep,
    Color? fill,
    Color? thumb,
    Color? glass,
    Color? blue,
    Color? green,
    Color? red,
    Color? orange,
    List<BoxShadow>? shadow,
  }) {
    return CloudPocketColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      bg: bg ?? this.bg,
      card: card ?? this.card,
      label: label ?? this.label,
      label2: label2 ?? this.label2,
      sep: sep ?? this.sep,
      fill: fill ?? this.fill,
      thumb: thumb ?? this.thumb,
      glass: glass ?? this.glass,
      blue: blue ?? this.blue,
      green: green ?? this.green,
      red: red ?? this.red,
      orange: orange ?? this.orange,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  CloudPocketColors lerp(covariant CloudPocketColors? other, double t) {
    if (other == null) return this;
    return CloudPocketColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      label: Color.lerp(label, other.label, t)!,
      label2: Color.lerp(label2, other.label2, t)!,
      sep: Color.lerp(sep, other.sep, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      thumb: Color.lerp(thumb, other.thumb, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      green: Color.lerp(green, other.green, t)!,
      red: Color.lerp(red, other.red, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      shadow: t < 0.5 ? shadow : other.shadow,
    );
  }
}

class CloudPocketTheme {
  CloudPocketTheme._();

  static const defaultSeed = Color(0xFF007AFF);

  // Motion curve from /design/cloudpocket.html: cubic-bezier(.32,.72,0,1)
  static const appleCurve = Cubic(0.32, 0.72, 0.0, 1.0);

  // Radii tokens
  static const double radiusCard = 26.0;
  static const double radiusGroup = 18.0;
  static const double radiusButton = 17.0;
  static const double radiusSegment = 12.0;
  static const double radiusSegmentThumb = 9.0;
  static const double radiusPill = 20.0;
  static const double radiusIconTile = 8.0;
  static const double radiusIconTileMedium = 11.0;
  static const double radiusIconTileLarge = 19.0;

  // Font fallback family
  static const List<String> fontFallbacks = [
    'SF Pro Text',
    'SF Pro Display',
    '-apple-system',
    'Inter',
    'Segoe UI',
    'Roboto',
  ];

  static ThemeData buildLightTheme([Color seed = defaultSeed]) {
    const cpColors = CloudPocketColors.light;
    final colorScheme = ColorScheme.light(
      primary: cpColors.blue,
      onPrimary: Colors.white,
      primaryContainer: cpColors.fill,
      onPrimaryContainer: cpColors.blue,
      secondary: cpColors.green,
      onSecondary: Colors.white,
      tertiary: cpColors.orange,
      surface: cpColors.bg,
      onSurface: cpColors.label,
      surfaceContainerHighest: cpColors.fill,
      onSurfaceVariant: cpColors.label2,
      outline: cpColors.sep,
      outlineVariant: cpColors.sep,
      error: cpColors.red,
      onError: Colors.white,
    );

    return _buildTheme(colorScheme, cpColors);
  }

  static ThemeData buildDarkTheme([Color seed = defaultSeed]) {
    const cpColors = CloudPocketColors.dark;
    final colorScheme = ColorScheme.dark(
      primary: cpColors.blue,
      onPrimary: Colors.white,
      primaryContainer: cpColors.fill,
      onPrimaryContainer: cpColors.blue,
      secondary: cpColors.green,
      onSecondary: Colors.white,
      tertiary: cpColors.orange,
      surface: cpColors.bg,
      onSurface: cpColors.label,
      surfaceContainerHighest: cpColors.fill,
      onSurfaceVariant: cpColors.label2,
      outline: cpColors.sep,
      outlineVariant: cpColors.sep,
      error: cpColors.red,
      onError: Colors.white,
    );

    return _buildTheme(colorScheme, cpColors);
  }

  static ThemeData get lightTheme => buildLightTheme();
  static ThemeData get darkTheme => buildDarkTheme();

  static ThemeData _buildTheme(ColorScheme colorScheme, CloudPocketColors cpColors) {
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: cpColors.bg,
      fontFamilyFallback: fontFallbacks,
      textTheme: TextTheme(
        // Large title: 34 bold -0.8px line-height 1.1
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.1,
          color: cpColors.label,
          fontFamilyFallback: fontFallbacks,
        ),
        // h1 / Title large
        titleLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.1,
          color: cpColors.label,
          fontFamilyFallback: fontFallbacks,
        ),
        // h2: 22 bold -0.4px
        titleMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: cpColors.label,
          fontFamilyFallback: fontFallbacks,
        ),
        // Body: 15
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: cpColors.label,
          fontFamilyFallback: fontFallbacks,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: cpColors.label,
          fontFamilyFallback: fontFallbacks,
        ),
        // Caption: 13
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: cpColors.label2,
          fontFamilyFallback: fontFallbacks,
        ),
        labelSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cpColors.label2,
          fontFamilyFallback: fontFallbacks,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: cpColors.label,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: cpColors.label,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          fontFamilyFallback: fontFallbacks,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cpColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: cpColors.fill,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cpColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: fontFallbacks,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cpColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: fontFallbacks,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cpColors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cpColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: cpColors.blue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        hintStyle: TextStyle(
          color: cpColors.label2,
          fontSize: 15,
          fontFamilyFallback: fontFallbacks,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cpColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cpColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusGroup)),
      ),
      dividerTheme: DividerThemeData(
        color: cpColors.sep,
        thickness: 0.5,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cpColors.green;
          }
          return cpColors.fill;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      extensions: [cpColors],
    );
  }
}
