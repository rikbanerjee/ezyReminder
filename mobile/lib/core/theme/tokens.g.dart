// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: design/tokens.json; generator: scripts/gen-tokens.mjs.
import 'dart:ui' show Color, FontWeight, Offset;
import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/painting.dart' show BoxShadow;

abstract final class EzyDesignTokens {
  // light palette
  static const Color lightBackground = Color(0xFFF7F6F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1A1A1A);
  static const Color lightText2 = Color(0xFF8A8A8E);
  static const Color lightHairline = Color(0xFFE5E4E0);
  static const Color lightWork = Color(0xFF3478F6);
  static const Color lightSidegig = Color(0xFFF5A623);
  static const Color lightSocial = Color(0xFF34C759);
  static const Color lightShopping = Color(0xFFAF52DE);
  static const Color lightDanger = Color(0xFFFF3B30);
  static const Color lightScrim = Color.fromRGBO(0, 0, 0, 0.4);
  static const BoxShadow lightCardShadow = BoxShadow(offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.05));
  static const BoxShadow lightSheetShadow = BoxShadow(offset: Offset(0, -8), blurRadius: 40, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.18));
  static const BoxShadow lightFloatShadow = BoxShadow(offset: Offset(0, 4), blurRadius: 20, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.12));
  // dark palette
  static const Color darkBackground = Color(0xFF111113);
  static const Color darkSurface = Color(0xFF1C1C1F);
  static const Color darkText = Color(0xFFF2F2F2);
  static const Color darkText2 = Color(0xFF98989E);
  static const Color darkHairline = Color(0xFF2C2C2E);
  static const Color darkWork = Color(0xFF4C8DFF);
  static const Color darkSidegig = Color(0xFFFFB340);
  static const Color darkSocial = Color(0xFF40D66B);
  static const Color darkShopping = Color(0xFFBF5AF2);
  static const Color darkDanger = Color(0xFFFF453A);
  static const Color darkScrim = Color.fromRGBO(0, 0, 0, 0.4);
  static const BoxShadow darkCardShadow = BoxShadow(offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.4));
  static const BoxShadow darkSheetShadow = BoxShadow(offset: Offset(0, -8), blurRadius: 40, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.5));
  static const BoxShadow darkFloatShadow = BoxShadow(offset: Offset(0, 4), blurRadius: 20, spreadRadius: 0, color: Color.fromRGBO(0, 0, 0, 0.45));

  // Uses Flutter’s platform system font; no SF Pro font is bundled.
  static const String? systemFontFamily = null;
  static const double spacingUnit = 4;
  static const double screenGutter = 16;
  static const double rowMinHeight = 52;
  static const double touchTargetMin = 44;
  static const double rowRadius = 12;
  static const double sheetRadius = 20;
  static const double pillRadius = 999;
  static const Duration sheetDuration = Duration(milliseconds: 300);
  static const Duration rowPopDuration = Duration(milliseconds: 200);
  static const Duration rowCollapseDuration = Duration(milliseconds: 250);
  static const Duration contextCrossfadeDuration = Duration(milliseconds: 150);
  static const Cubic sheetCurve = Cubic(0.32, 0.72, 0, 1);
  static const double rowPopScaleStart = 1;
  static const double rowPopScalePeak = 1.15;
  static const double rowPopScaleEnd = 1;
  static const double scrimOpacity = 0.4;
  static const double screenTitleFontSize = 28;
  static const FontWeight screenTitleFontWeight = FontWeight.w700;
  static const double rowTitleFontSize = 17;
  static const FontWeight rowTitleFontWeight = FontWeight.w600;
  static const double notesPreviewFontSize = 15;
  static const FontWeight notesPreviewFontWeight = FontWeight.w400;
  static const double dueChipFontSize = 13;
  static const FontWeight dueChipFontWeight = FontWeight.w500;
  static const double sectionHeaderFontSize = 13;
  static const FontWeight sectionHeaderFontWeight = FontWeight.w500;
  static const double sectionHeaderLetterSpacing = 0.6;
}
