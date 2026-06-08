import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's brand mark: the orange `restaurant_menu` glyph (the same icon used
/// as the no-image recipe placeholder) followed by the "Recipes" wordmark.
/// Used in the side nav header and on the login screen so the logo is identical
/// everywhere. The icon takes the accent (orange) token; the wordmark takes
/// `ink`, so both adapt to light/dark automatically.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.iconSize = 22, this.fontSize = 20});

  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.restaurant_menu, size: iconSize, color: rt.accent),
        SizedBox(width: iconSize * 0.42),
        Text(
          'Recipes',
          semanticsLabel: 'Recipes',
          style: RecipeTypography.serif(
            size: fontSize,
            weight: FontWeight.w500,
            color: rt.ink,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}
