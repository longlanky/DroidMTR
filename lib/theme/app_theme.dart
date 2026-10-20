import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.good,
    required this.warning,
    required this.bad,
    required this.info,
    required this.grid,
    required this.glow,
  });

  final Color good;
  final Color warning;
  final Color bad;
  final Color info;
  final Color grid;
  final Color glow;

  static const light = AppColors(
    good: Color(0xFF0F9D76),
    warning: Color(0xFFE09A15),
    bad: Color(0xFFE34D59),
    info: Color(0xFF3B82F6),
    grid: Color(0xFFE4EAF0),
    glow: Color(0x1A0F766E),
  );

  static const dark = AppColors(
    good: Color(0xFF42D6AE),
    warning: Color(0xFFF4C05A),
    bad: Color(0xFFFF7A86),
    info: Color(0xFF7DB4FF),
    grid: Color(0xFF243140),
    glow: Color(0x335EEAD4),
  );

  @override
  AppColors copyWith({
    Color? good,
    Color? warning,
    Color? bad,
    Color? info,
    Color? grid,
    Color? glow,
  }) {
    return AppColors(
      good: good ?? this.good,
      warning: warning ?? this.warning,
      bad: bad ?? this.bad,
      info: info ?? this.info,
      grid: grid ?? this.grid,
      glow: glow ?? this.glow,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      info: Color.lerp(info, other.info, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

class AppTheme {
  static const _lightPrimary = Color(0xFF0F766E);
  static const _lightInk = Color(0xFF0B1520);
  static const _lightMuted = Color(0xFF687385);
  static const _lightBg = Color(0xFFF5F7FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightOutline = Color(0xFFE1E7EE);

  static const _darkPrimary = Color(0xFF5EEAD4);
  static const _darkInk = Color(0xFFE8EEF6);
  static const _darkMuted = Color(0xFF98A6B8);
  static const _darkBg = Color(0xFF080C11);
  static const _darkSurface = Color(0xFF111820);
  static const _darkOutline = Color(0xFF243140);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _lightPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: _lightPrimary,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFDDF5EF),
          onPrimaryContainer: const Color(0xFF003B36),
          secondary: const Color(0xFF3F5F5B),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFE2EFEC),
          onSecondaryContainer: const Color(0xFF162B28),
          tertiary: const Color(0xFF2563EB),
          surface: _lightSurface,
          onSurface: _lightInk,
          onSurfaceVariant: _lightMuted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFAFBFC),
          surfaceContainer: const Color(0xFFF0F4F8),
          surfaceContainerHigh: const Color(0xFFEAF0F5),
          surfaceContainerHighest: const Color(0xFFE6ECF2),
          outline: const Color(0xFFC8D2DD),
          outlineVariant: _lightOutline,
          error: const Color(0xFFD43D4B),
          errorContainer: const Color(0xFFFFE4E6),
          onErrorContainer: const Color(0xFF6A111B),
          shadow: const Color(0x1A0B1520),
          scrim: const Color(0x66000000),
          surfaceTint: Colors.transparent,
        );
    return _build(
      scheme: scheme,
      scaffold: _lightBg,
      card: _lightSurface,
      ink: _lightInk,
      muted: _lightMuted,
      outline: _lightOutline,
      appColors: AppColors.light,
      brightness: Brightness.light,
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _darkPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _darkPrimary,
          onPrimary: const Color(0xFF003731),
          primaryContainer: const Color(0xFF12443E),
          onPrimaryContainer: const Color(0xFFB8F7E9),
          secondary: const Color(0xFFA9C4BF),
          onSecondary: const Color(0xFF102A26),
          secondaryContainer: const Color(0xFF1A302C),
          onSecondaryContainer: const Color(0xFFD1E8E3),
          tertiary: const Color(0xFF8AB4FF),
          surface: _darkSurface,
          onSurface: _darkInk,
          onSurfaceVariant: _darkMuted,
          surfaceContainerLowest: const Color(0xFF080C11),
          surfaceContainerLow: const Color(0xFF0D131A),
          surfaceContainer: const Color(0xFF131C25),
          surfaceContainerHigh: const Color(0xFF18232D),
          surfaceContainerHighest: const Color(0xFF1D2935),
          outline: const Color(0xFF3B4B5C),
          outlineVariant: _darkOutline,
          error: const Color(0xFFFF7A86),
          errorContainer: const Color(0xFF4E1720),
          onErrorContainer: const Color(0xFFFFD9DD),
          shadow: const Color(0x66000000),
          scrim: const Color(0x99000000),
          surfaceTint: Colors.transparent,
        );
    return _build(
      scheme: scheme,
      scaffold: _darkBg,
      card: _darkSurface,
      ink: _darkInk,
      muted: _darkMuted,
      outline: _darkOutline,
      appColors: AppColors.dark,
      brightness: Brightness.dark,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color ink,
    required Color muted,
    required Color outline,
    required AppColors appColors,
    required Brightness brightness,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: ink,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: ink,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: ink,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: ink,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.45,
        color: ink,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        color: ink,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        color: muted,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: muted,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: muted,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: ink,
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(44, 44),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? scheme.onPrimaryContainer : muted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF1E2A35)
            : const Color(0xFF15202B),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: outline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: outline),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return outline;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? const Color(0xFF243240)
              : const Color(0xFF17222D),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }

  static Color latencyColor(AppColors colors, double? ms) {
    if (ms == null || ms <= 0) return colors.info;
    if (ms < 60) return colors.good;
    if (ms < 150) return colors.warning;
    return colors.bad;
  }

  static String latencyLabel(double? ms) {
    if (ms == null || ms <= 0) return 'No data';
    if (ms < 60) return 'Fast';
    if (ms < 150) return 'Moderate';
    return 'Slow';
  }
}
