import 'package:flutter/material.dart';

abstract final class Brand {
  static const name = 'Food Delivery Demo';
}

abstract final class Space {
  static const double page = 24, gap = 16, radius = 20;
}

abstract final class AppType {
  // Build-time comparison only; a running app uses exactly two families.
  static const editorial = String.fromEnvironment(
    'EDITORIAL_FONT',
    defaultValue: 'BricolageGrotesque',
  );
  static const ui = 'Sora';
  static TextStyle heading(double size, Color color) => TextStyle(
    fontFamily: editorial,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.12,
    letterSpacing: size >= 28 ? -.7 : -.35,
    color: color,
  );
  static TextStyle functional(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: ui,
    fontSize: size,
    height: 1.5,
    letterSpacing: -.15,
    fontWeight: weight,
    color: color,
  );
}

@immutable
class CulinaryColors extends ThemeExtension<CulinaryColors> {
  final Color peach, saffron, pistachio, seaGlass;
  const CulinaryColors({
    required this.peach,
    required this.saffron,
    required this.pistachio,
    required this.seaGlass,
  });
  @override
  CulinaryColors copyWith({
    Color? peach,
    Color? saffron,
    Color? pistachio,
    Color? seaGlass,
  }) => CulinaryColors(
    peach: peach ?? this.peach,
    saffron: saffron ?? this.saffron,
    pistachio: pistachio ?? this.pistachio,
    seaGlass: seaGlass ?? this.seaGlass,
  );
  @override
  CulinaryColors lerp(covariant CulinaryColors? other, double t) =>
      other == null
      ? this
      : CulinaryColors(
          peach: Color.lerp(peach, other.peach, t)!,
          saffron: Color.lerp(saffron, other.saffron, t)!,
          pistachio: Color.lerp(pistachio, other.pistachio, t)!,
          seaGlass: Color.lerp(seaGlass, other.seaGlass, t)!,
        );
}

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = CulinaryColors(
    peach: Color(dark ? 0xFF493329 : 0xFFF4D3C1),
    saffron: Color(dark ? 0xFF51402A : 0xFFE8B96C),
    pistachio: Color(dark ? 0xFF2A4035 : 0xFFDAE7D7),
    seaGlass: Color(dark ? 0xFF2B4443 : 0xFFD6E9E5),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9C4A38),
    brightness: brightness,
    primary: Color(dark ? 0xFFD5A077 : 0xFF9C4A38),
    onPrimary: Color(dark ? 0xFF232B27 : 0xFFFFFFFF),
    primaryContainer: colors.peach,
    onPrimaryContainer: Color(dark ? 0xFFF7F1E8 : 0xFF232B27),
    secondary: Color(dark ? 0xFF98AA90 : 0xFF47624E),
    secondaryContainer: colors.pistachio,
    onSecondaryContainer: Color(dark ? 0xFFF7F1E8 : 0xFF232B27),
    surface: Color(dark ? 0xFF121513 : 0xFFFAF8F4),
    onSurface: Color(dark ? 0xFFF7F1E8 : 0xFF232B27),
    surfaceContainer: Color(dark ? 0xFF1D211E : 0xFFF3EEE7),
    surfaceContainerHigh: Color(dark ? 0xFF292F29 : 0xFFE5D6BF),
    onSurfaceVariant: Color(dark ? 0xFFC2C8BF : 0xFF5A645C),
    outlineVariant: Color(dark ? 0xFF394239 : 0xFFDEDCD3),
  );
  final text = TextTheme(
    headlineLarge: AppType.heading(34, scheme.onSurface),
    headlineMedium: AppType.heading(28, scheme.onSurface),
    titleLarge: AppType.heading(23, scheme.onSurface),
    titleMedium: AppType.functional(
      15,
      scheme.onSurface,
      weight: FontWeight.w600,
    ),
    titleSmall: AppType.functional(
      14,
      scheme.onSurface,
      weight: FontWeight.w600,
    ),
    bodyLarge: AppType.functional(15, scheme.onSurface),
    bodyMedium: AppType.functional(13, scheme.onSurface),
    bodySmall: AppType.functional(11, scheme.onSurfaceVariant),
    labelLarge: AppType.functional(
      12,
      scheme.onSurface,
      weight: FontWeight.w600,
    ),
    labelMedium: AppType.functional(
      11,
      scheme.onSurface,
      weight: FontWeight.w500,
    ),
    labelSmall: AppType.functional(
      10,
      scheme.onSurfaceVariant,
      weight: FontWeight.w600,
    ),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppType.ui,
    textTheme: text,
    extensions: [colors],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 32,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: colors.peach,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surface,
      selectedColor: colors.pistachio,
      labelStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
