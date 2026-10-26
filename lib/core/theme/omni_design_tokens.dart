import 'package:flutter/material.dart';

/// Canonical visual tokens for the Omni Tools mobile shell and core screens.
///
/// These values intentionally translate the Omni Internal visual language to
/// the Omni Tools mobile identity. The cyan brand accent remains primary on
/// mobile; internal-system blue is not copied as a replacement accent.
class OmniDesignTokens {
  const OmniDesignTokens._();

  // Brand and semantic colours.
  static const Color primary = Color(0xFF1FC6C1);
  static const Color primaryPressed = Color(0xFF18AAA6);
  static const Color primarySoft = Color(0x1F1FC6C1);
  static const Color primarySubtle = Color(0x141FC6C1);

  // Deep teal for text/gradients that need stronger contrast than [primary].
  static const Color primaryDeep = Color(0xFF0B7F86);
  static const Color primaryGradientEnd = Color(0xFF0E9FB5);
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryGradientEnd],
  );
  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12B5B0), primaryDeep],
  );

  static const Color canvas = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F7);
  static const Color header = canvas;
  static const Color border = Color(0xFFE1E7EB);
  static const Color borderStrong = Color(0xFFD2D9DE);

  static const Color textPrimary = Color(0xFF202124);
  static const Color textSecondary = Color(0xFF3C4043);
  static const Color textMuted = Color(0xFF5F6368);

  static const Color success = Color(0xFF137333);
  static const Color successSurface = Color(0xFFE6F4EA);
  static const Color warning = Color(0xFF795500);
  static const Color warningSurface = Color(0xFFFEF7E0);
  static const Color error = Color(0xFFA50E0E);
  static const Color errorSurface = Color(0xFFFCE8E6);

  // Dark-theme roles. These stay explicit so dark safety does not depend on
  // ad-hoc inverse colours inside individual screens.
  static const Color darkCanvas = Color(0xFF121516);
  static const Color darkSurface = Color(0xFF1B2021);
  static const Color darkHeader = Color(0xFF171B1C);
  static const Color darkBorder = Color(0xFF303839);
  static const Color darkBorderStrong = Color(0xFF566162);
  static const Color darkTextPrimary = Color(0xFFF4F7F7);
  static const Color darkTextSecondary = Color(0xFFB6C0C0);
  static const Color darkPrimarySoft = Color(0x3332D5CF);

  // Controlled secondary accents for tool categories.
  static const Color categoryQr = Color(0xFF00AEB4);
  static const Color categoryLinks = Color(0xFFE0523F);
  static const Color categoryDevice = Color(0xFF7A8F3A);
  static const Color categoryDeveloper = Color(0xFF3F7F8C);
  static const Color categoryBusiness = Color(0xFFB8741A);
  static const Color categoryNfc = Color(0xFF5967C8);
  static const Color categoryText = Color(0xFF9A4DB1);
  static const Color categoryFiles = Color(0xFFE58A21);
  static const Color categoryConverters = Color(0xFF3D8FE5);
  static const Color categoryCalculator = Color(0xFF4EAA68);

  // Layout and geometry.
  static const double pageInset = 16;
  static const double compactInset = 12;
  static const double sectionGap = 24;
  static const double cardPadding = 16;
  static const double controlHeight = 48;
  static const double iconButtonSize = 48;

  static const double radiusControl = 12;
  static const double radiusCompactCard = 16;
  static const double radiusCard = 20;
  static const double radiusLargeCard = 24;
  static const double radiusPill = 999;

  // Typography scale.
  static const double pageTitleSize = 24;
  static const double sectionTitleSize = 18;
  static const double cardTitleSize = 16;
  static const double bodySize = 14;
  static const double metadataSize = 12;
  static const double helperSize = 11;
  static const double bodyLineHeight = 1.4;
  static const FontWeight titleWeight = FontWeight.w700;
  static const FontWeight actionWeight = FontWeight.w600;
  static const FontWeight bodyWeight = FontWeight.w400;

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x12202124),
    blurRadius: 14,
    offset: Offset(0, 4),
  );

  static const BoxShadow elevatedShadow = BoxShadow(
    color: Color(0x1F202124),
    blurRadius: 24,
    offset: Offset(0, 10),
  );

  /// Accent used for tip / highlight surfaces.
  static const Color accentAmber = Color(0xFFF2A413);
  static const Color accentAmberSurface = Color(0xFFFFF6E0);

  static const String fontFamily = 'Poppins';

  static const Duration fastMotion = Duration(milliseconds: 150);
  static const Duration mediumMotion = Duration(milliseconds: 220);
}
