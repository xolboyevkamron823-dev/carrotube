import 'package:flutter/material.dart';

/// YouTube-like colours.
abstract final class YtColors {
  static const red = Color(0xFFFF0000);
  static const darkBg = Color(0xFF0F0F0F);
  static const darkSurface = Color(0xFF212121);
  static const darkSurfaceHigh = Color(0xFF272727);
  static const darkText = Color(0xFFF1F1F1);
  static const darkTextSecondary = Color(0xFFAAAAAA);
  static const lightBg = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF2F2F2);
  static const lightText = Color(0xFF0F0F0F);
  static const lightTextSecondary = Color(0xFF606060);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? Colors.white : Colors.black,
    onPrimary: dark ? Colors.black : Colors.white,
    secondary: YtColors.red,
    onSecondary: Colors.white,
    error: const Color(0xFFCF6679),
    onError: Colors.black,
    surface: dark ? YtColors.darkBg : YtColors.lightBg,
    onSurface: dark ? YtColors.darkText : YtColors.lightText,
    surfaceContainerHighest: dark ? YtColors.darkSurfaceHigh : YtColors.lightSurface,
    surfaceContainerHigh: dark ? YtColors.darkSurface : YtColors.lightSurface,
    surfaceContainer: dark ? YtColors.darkSurface : YtColors.lightSurface,
    surfaceContainerLow: dark ? const Color(0xFF181818) : const Color(0xFFF8F8F8),
    onSurfaceVariant: dark ? YtColors.darkTextSecondary : YtColors.lightTextSecondary,
    outline: dark ? const Color(0xFF3F3F3F) : const Color(0xFFD9D9D9),
    outlineVariant: dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: Colors.transparent,
      height: 56,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelSmall?.copyWith(fontSize: 10)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.onSurface,
      labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
      secondaryLabelStyle: TextStyle(color: scheme.surface, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? YtColors.darkSurface : YtColors.lightBg,
      showDragHandle: true,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: YtColors.red,
      thumbColor: YtColors.red,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.25),
      overlayShape: SliderComponentShape.noOverlay,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: YtColors.red),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
