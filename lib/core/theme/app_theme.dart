import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ShadThemeData buildSeilShadTheme() {
  return ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadZincColorScheme.light(),
    radius: BorderRadius.circular(8),
    textTheme: ShadTextTheme(family: 'Pretendard'),
  );
}

ThemeData buildSeilTheme() {
  const background = Color(0xFFF8FAFC);
  const foreground = Color(0xFF0F172A);
  const card = Color(0xFFFFFFFF);
  const muted = Color(0xFFEFF6FF);
  const mutedForeground = Color(0xFF64748B);
  const border = Color(0xFFD8E0EA);
  const input = Color(0xFFD8E0EA);
  const primary = Color(0xFF4F46E5);
  const primaryForeground = Color(0xFFFAFAFA);
  const destructive = Color(0xFFDC2626);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Pretendard',
    fontFamilyFallback: const [
      'SF Pro Text',
      'Roboto',
      'Noto Sans KR',
    ],
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: primaryForeground,
      secondary: muted,
      onSecondary: foreground,
      surface: card,
      onSurface: foreground,
      surfaceContainerHighest: Color(0xFFEFF6FF),
      outline: border,
      error: destructive,
      onError: primaryForeground,
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontWeight: FontWeight.w700, color: foreground),
      headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: foreground),
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: foreground),
      titleLarge: TextStyle(fontWeight: FontWeight.w600, color: foreground),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: foreground),
      labelLarge: TextStyle(fontWeight: FontWeight.w600, color: foreground),
      bodyMedium: TextStyle(color: foreground),
      bodySmall: TextStyle(color: mutedForeground),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0.5,
      shadowColor: const Color(0x1A0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: primary),
      ),
      labelStyle: const TextStyle(color: mutedForeground),
      prefixIconColor: mutedForeground,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        backgroundColor: primary,
        foregroundColor: primaryForeground,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 40),
        foregroundColor: foreground,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  );
}
