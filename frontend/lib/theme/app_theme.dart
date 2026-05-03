import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Design tokens ported from recipes-wireframe/project/Recipes.html (lines 11-51).
// `oklch(...)` values from the source CSS were converted to approximate sRGB.

class RecipeColors {
  // Light palette
  static const paperLight = Color(0xFFFAF7F2);
  static const paper2Light = Color(0xFFF3EFE7);
  static const inkLight = Color(0xFF1A1714);
  static const ink2Light = Color(0xFF3D3833);
  static const ink3Light = Color(0xFF6B655D);
  static const hairLight = Color(0xFFE2DCD0);
  static const hair2Light = Color(0xFFD4CCBC);
  static const accentLight = Color(0xFFBC6A37);
  static const accentSoftLight = Color(0x14BC6A37);
  static const accentInkLight = Color(0xFF7A4322);
  static const dangerLight = Color(0xFFA93A20);
  static const okLight = Color(0xFF648B53);
  static const imgTintLight = Color(0xEBFAF7F2);
  static const modalShadowLight = Color(0x26000000);
  static const toastShadowLight = Color(0x2E000000);
  static const backdropLight = Color(0x731A1714);

  // Dark palette
  static const paperDark = Color(0xFF15130F);
  static const paper2Dark = Color(0xFF1F1C17);
  static const inkDark = Color(0xFFF2EDE3);
  static const ink2Dark = Color(0xFFC9C2B5);
  static const ink3Dark = Color(0xFF867E70);
  static const hairDark = Color(0xFF2C2820);
  static const hair2Dark = Color(0xFF3A3528);
  static const accentDark = Color(0xFFD89460);
  static const accentSoftDark = Color(0x24D89460);
  static const accentInkDark = Color(0xFFE0A776);
  static const dangerDark = Color(0xFFDD7E62);
  static const okDark = Color(0xFF75BF7E);
  static const imgTintDark = Color(0xD915130F);
  static const modalShadowDark = Color(0x80000000);
  static const toastShadowDark = Color(0x99000000);
  static const backdropDark = Color(0x99000000);
}

class RecipeRadius {
  static const Radius card = Radius.circular(10);
  static const Radius field = Radius.circular(6);
  static const Radius chip = Radius.circular(999);

  static const BorderRadius cardBR = BorderRadius.all(card);
  static const BorderRadius fieldBR = BorderRadius.all(field);
  static const BorderRadius chipBR = BorderRadius.all(chip);
}

class RecipeTheme extends ThemeExtension<RecipeTheme> {
  const RecipeTheme({
    required this.paper,
    required this.paper2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hair,
    required this.hair2,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.danger,
    required this.ok,
    required this.imgTint,
    required this.modalShadow,
    required this.toastShadow,
    required this.backdrop,
  });

  final Color paper;
  final Color paper2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color hair;
  final Color hair2;
  final Color accent;
  final Color accentSoft;
  final Color accentInk;
  final Color danger;
  final Color ok;
  final Color imgTint;
  final Color modalShadow;
  final Color toastShadow;
  final Color backdrop;

  static const RecipeTheme light = RecipeTheme(
    paper: RecipeColors.paperLight,
    paper2: RecipeColors.paper2Light,
    ink: RecipeColors.inkLight,
    ink2: RecipeColors.ink2Light,
    ink3: RecipeColors.ink3Light,
    hair: RecipeColors.hairLight,
    hair2: RecipeColors.hair2Light,
    accent: RecipeColors.accentLight,
    accentSoft: RecipeColors.accentSoftLight,
    accentInk: RecipeColors.accentInkLight,
    danger: RecipeColors.dangerLight,
    ok: RecipeColors.okLight,
    imgTint: RecipeColors.imgTintLight,
    modalShadow: RecipeColors.modalShadowLight,
    toastShadow: RecipeColors.toastShadowLight,
    backdrop: RecipeColors.backdropLight,
  );

  static const RecipeTheme dark = RecipeTheme(
    paper: RecipeColors.paperDark,
    paper2: RecipeColors.paper2Dark,
    ink: RecipeColors.inkDark,
    ink2: RecipeColors.ink2Dark,
    ink3: RecipeColors.ink3Dark,
    hair: RecipeColors.hairDark,
    hair2: RecipeColors.hair2Dark,
    accent: RecipeColors.accentDark,
    accentSoft: RecipeColors.accentSoftDark,
    accentInk: RecipeColors.accentInkDark,
    danger: RecipeColors.dangerDark,
    ok: RecipeColors.okDark,
    imgTint: RecipeColors.imgTintDark,
    modalShadow: RecipeColors.modalShadowDark,
    toastShadow: RecipeColors.toastShadowDark,
    backdrop: RecipeColors.backdropDark,
  );

  @override
  RecipeTheme copyWith({
    Color? paper, Color? paper2,
    Color? ink, Color? ink2, Color? ink3,
    Color? hair, Color? hair2,
    Color? accent, Color? accentSoft, Color? accentInk,
    Color? danger, Color? ok,
    Color? imgTint, Color? modalShadow, Color? toastShadow, Color? backdrop,
  }) => RecipeTheme(
    paper: paper ?? this.paper,
    paper2: paper2 ?? this.paper2,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    ink3: ink3 ?? this.ink3,
    hair: hair ?? this.hair,
    hair2: hair2 ?? this.hair2,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    accentInk: accentInk ?? this.accentInk,
    danger: danger ?? this.danger,
    ok: ok ?? this.ok,
    imgTint: imgTint ?? this.imgTint,
    modalShadow: modalShadow ?? this.modalShadow,
    toastShadow: toastShadow ?? this.toastShadow,
    backdrop: backdrop ?? this.backdrop,
  );

  @override
  RecipeTheme lerp(RecipeTheme? other, double t) {
    if (other == null) return this;
    return RecipeTheme(
      paper: Color.lerp(paper, other.paper, t)!,
      paper2: Color.lerp(paper2, other.paper2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      hair: Color.lerp(hair, other.hair, t)!,
      hair2: Color.lerp(hair2, other.hair2, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      imgTint: Color.lerp(imgTint, other.imgTint, t)!,
      modalShadow: Color.lerp(modalShadow, other.modalShadow, t)!,
      toastShadow: Color.lerp(toastShadow, other.toastShadow, t)!,
      backdrop: Color.lerp(backdrop, other.backdrop, t)!,
    );
  }
}

// Typography helpers — three font families pulled via google_fonts.
class RecipeTypography {
  static TextStyle sans({double size = 15, FontWeight weight = FontWeight.w400, Color? color, double? height, double? letterSpacing}) =>
      GoogleFonts.interTight(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: letterSpacing);

  static TextStyle serif({double size = 18, FontWeight weight = FontWeight.w500, Color? color, double? height, double? letterSpacing}) =>
      GoogleFonts.newsreader(fontSize: size, fontWeight: weight, color: color, height: height ?? 1.2, letterSpacing: letterSpacing ?? -0.01 * size);

  static TextStyle mono({double size = 12, FontWeight weight = FontWeight.w400, Color? color, double? letterSpacing}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing ?? 0.04 * size);
}

ThemeData buildTheme(Brightness brightness) {
  final rt = brightness == Brightness.light ? RecipeTheme.light : RecipeTheme.dark;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: rt.paper,
    canvasColor: rt.paper,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: rt.ink,
      onPrimary: rt.paper,
      secondary: rt.accent,
      onSecondary: Colors.white,
      error: rt.danger,
      onError: Colors.white,
      surface: rt.paper,
      onSurface: rt.ink,
    ),
    textTheme: GoogleFonts.interTightTextTheme(
      brightness == Brightness.light ? ThemeData.light().textTheme : ThemeData.dark().textTheme,
    ).apply(bodyColor: rt.ink, displayColor: rt.ink),
    useMaterial3: true,
    extensions: [rt],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}

extension RecipeThemeContext on BuildContext {
  RecipeTheme get rt => Theme.of(this).extension<RecipeTheme>()!;
}
