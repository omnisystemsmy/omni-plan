import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_page_transitions.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// Application theme entry point.
///
/// Core screens should consume these roles rather than introducing new local
/// colours, radii, or shadow conventions.
class AppThemes {
  static ThemeData get lightTheme => _withSharedComponents(_buildLightTheme());

  static ThemeData get darkTheme => _withSharedComponents(_buildDarkTheme());

  /// Component themes shared by light and dark so raw Material widgets used
  /// across the calculator pages pick up the same shape, colour and contrast.
  static ThemeData _withSharedComponents(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final cs = base.colorScheme;
    final selected = cs.primary;
    final trackBorder = isDark
        ? OmniDesignTokens.darkBorder
        : OmniDesignTokens.border;
    final idleText = isDark
        ? OmniDesignTokens.darkTextSecondary
        : OmniDesignTokens.textSecondary;

    return base.copyWith(
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? selected : cs.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : idleText,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : idleText,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: trackBorder)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: OmniDesignTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      toggleButtonsTheme: ToggleButtonsThemeData(
        color: idleText,
        selectedColor: Colors.white,
        fillColor: selected,
        borderColor: trackBorder,
        selectedBorderColor: selected,
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
        textStyle: const TextStyle(
          fontFamily: OmniDesignTokens.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: selected,
        backgroundColor: cs.surface,
        checkmarkColor: Colors.white,
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        labelStyle: TextStyle(color: idleText, fontWeight: FontWeight.w600),
        shape: StadiumBorder(side: BorderSide(color: trackBorder)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: selected,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        dividerColor: trackBorder,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? selected : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? selected : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? selected : null,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, OmniDesignTokens.controlHeight),
          foregroundColor: selected,
          side: BorderSide(color: selected.withValues(alpha: 0.5)),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: OmniDesignTokens.fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    final colorScheme = const ColorScheme.light(
      primary: OmniDesignTokens.primary,
      onPrimary: Colors.white,
      primaryContainer: OmniDesignTokens.primarySoft,
      onPrimaryContainer: OmniDesignTokens.textPrimary,
      secondary: OmniDesignTokens.categoryConverters,
      onSecondary: Colors.white,
      tertiary: OmniDesignTokens.categoryCalculator,
      error: OmniDesignTokens.error,
      onError: Colors.white,
      surface: OmniDesignTokens.surface,
      onSurface: OmniDesignTokens.textPrimary,
      onSurfaceVariant: OmniDesignTokens.textMuted,
      outline: OmniDesignTokens.borderStrong,
      outlineVariant: OmniDesignTokens.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: omniPageTransitions,
      splashFactory: InkSparkle.splashFactory,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamily: OmniDesignTokens.fontFamily,
    );

    return base.copyWith(
      scaffoldBackgroundColor: OmniDesignTokens.canvas,
      cardColor: OmniDesignTokens.surface,
      shadowColor: const Color(0xFF202124),
      appBarTheme: const AppBarTheme(
        backgroundColor: OmniDesignTokens.header,
        foregroundColor: OmniDesignTokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
      ),
      textTheme: _textTheme(OmniDesignTokens.textPrimary),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, OmniDesignTokens.controlHeight),
          backgroundColor: OmniDesignTokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
          ),
          textStyle: const TextStyle(
            fontFamily: OmniDesignTokens.fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, OmniDesignTokens.controlHeight),
          backgroundColor: OmniDesignTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, OmniDesignTokens.controlHeight),
          foregroundColor: OmniDesignTokens.primaryPressed,
          textStyle: const TextStyle(
            fontFamily: OmniDesignTokens.fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: _inputDecorationTheme(
        fillColor: OmniDesignTokens.surface,
        borderColor: OmniDesignTokens.border,
        focusColor: OmniDesignTokens.primary,
        textColor: OmniDesignTokens.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: OmniDesignTokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
          side: const BorderSide(color: OmniDesignTokens.border),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: OmniDesignTokens.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: OmniDesignTokens.surface,
        selectedItemColor: OmniDesignTokens.primary,
        unselectedItemColor: OmniDesignTokens.textMuted,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: OmniDesignTokens.surface,
        indicatorColor: OmniDesignTokens.primarySoft,
      ),
      dividerTheme: const DividerThemeData(
        color: OmniDesignTokens.border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: OmniDesignTokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusLargeCard),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: OmniDesignTokens.surface,
        modalBackgroundColor: OmniDesignTokens.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: OmniDesignTokens.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
        ),
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    final colorScheme = const ColorScheme.dark(
      primary: OmniDesignTokens.primary,
      onPrimary: Colors.white,
      primaryContainer: OmniDesignTokens.darkPrimarySoft,
      onPrimaryContainer: OmniDesignTokens.darkTextPrimary,
      secondary: Color(0xFF75C8F2),
      onSecondary: Colors.black,
      tertiary: Color(0xFF8BCB9B),
      onTertiary: Colors.black,
      error: Color(0xFFFF8A80),
      onError: Colors.black,
      surface: OmniDesignTokens.darkSurface,
      onSurface: OmniDesignTokens.darkTextPrimary,
      onSurfaceVariant: OmniDesignTokens.darkTextSecondary,
      outline: OmniDesignTokens.darkBorderStrong,
      outlineVariant: OmniDesignTokens.darkBorder,
    );

    final base = ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: omniPageTransitions,
      splashFactory: InkSparkle.splashFactory,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamily: OmniDesignTokens.fontFamily,
    );

    return base.copyWith(
      scaffoldBackgroundColor: OmniDesignTokens.darkCanvas,
      cardColor: OmniDesignTokens.darkSurface,
      shadowColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: OmniDesignTokens.darkHeader,
        foregroundColor: OmniDesignTokens.darkTextPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
      ),
      textTheme: _textTheme(OmniDesignTokens.darkTextPrimary).apply(
        bodyColor: OmniDesignTokens.darkTextPrimary,
        displayColor: OmniDesignTokens.darkTextPrimary,
      ),
      inputDecorationTheme: _inputDecorationTheme(
        fillColor: OmniDesignTokens.darkSurface,
        borderColor: OmniDesignTokens.darkBorder,
        focusColor: OmniDesignTokens.primary,
        textColor: OmniDesignTokens.darkTextPrimary,
      ),
      cardTheme: CardThemeData(
        color: OmniDesignTokens.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
          side: const BorderSide(color: OmniDesignTokens.darkBorder),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: OmniDesignTokens.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: OmniDesignTokens.darkSurface,
        selectedItemColor: OmniDesignTokens.primary,
        unselectedItemColor: OmniDesignTokens.darkTextSecondary,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: OmniDesignTokens.darkSurface,
        indicatorColor: OmniDesignTokens.darkPrimarySoft,
      ),
      dividerTheme: const DividerThemeData(
        color: OmniDesignTokens.darkBorder,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: OmniDesignTokens.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: OmniDesignTokens.darkSurface,
        modalBackgroundColor: OmniDesignTokens.darkSurface,
      ),
    );
  }

  static TextTheme _textTheme(Color primaryText) {
    return _rawTextTheme(primaryText)
        .apply(fontFamily: OmniDesignTokens.fontFamily);
  }

  static TextTheme _rawTextTheme(Color primaryText) {
    return TextTheme(
      displayLarge: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.pageTitleSize + 8,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      displayMedium: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.pageTitleSize + 4,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      displaySmall: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.pageTitleSize,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      headlineLarge: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.pageTitleSize,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      headlineMedium: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.pageTitleSize - 4,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      headlineSmall: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.sectionTitleSize,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      titleLarge: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.sectionTitleSize,
        fontWeight: OmniDesignTokens.titleWeight,
      ),
      titleMedium: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.cardTitleSize,
        fontWeight: OmniDesignTokens.actionWeight,
      ),
      titleSmall: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.bodySize,
        fontWeight: OmniDesignTokens.actionWeight,
      ),
      bodyLarge: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.cardTitleSize,
        height: OmniDesignTokens.bodyLineHeight,
      ),
      bodyMedium: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.bodySize,
        height: OmniDesignTokens.bodyLineHeight,
      ),
      bodySmall: const TextStyle(
        color: OmniDesignTokens.textMuted,
        fontSize: OmniDesignTokens.metadataSize,
        height: OmniDesignTokens.bodyLineHeight,
      ),
      labelLarge: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.bodySize,
        fontWeight: OmniDesignTokens.actionWeight,
      ),
      labelMedium: TextStyle(
        color: primaryText,
        fontSize: OmniDesignTokens.metadataSize,
        fontWeight: OmniDesignTokens.actionWeight,
      ),
      labelSmall: const TextStyle(
        color: OmniDesignTokens.textMuted,
        fontSize: OmniDesignTokens.helperSize,
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme({
    required Color fillColor,
    required Color borderColor,
    required Color focusColor,
    required Color textColor,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      prefixIconColor: OmniDesignTokens.textMuted,
      suffixIconColor: OmniDesignTokens.textMuted,
      hintStyle: const TextStyle(
        color: OmniDesignTokens.textMuted,
        fontSize: 14,
      ),
      labelStyle: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      border: border(borderColor),
      enabledBorder: border(borderColor),
      focusedBorder: border(focusColor, 1.5),
      errorBorder: border(OmniDesignTokens.error),
      focusedErrorBorder: border(OmniDesignTokens.error, 1.5),
    );
  }
}
