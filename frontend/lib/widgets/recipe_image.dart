import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Renders a recipe's image with a tasteful themed fallback when the URL is
/// empty or fails to load. Used by the recipe card and the detail hero so the
/// placeholder looks identical everywhere.
class RecipeImage extends StatelessWidget {
  const RecipeImage({super.key, required this.url, this.iconSize = 28});

  /// Possibly-empty image URL (`recipe.image`).
  final String url;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _Placeholder(iconSize: iconSize);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _Placeholder(iconSize: iconSize),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.iconSize});
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      color: rt.paper2,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_menu, size: iconSize, color: rt.ink3),
    );
  }
}
