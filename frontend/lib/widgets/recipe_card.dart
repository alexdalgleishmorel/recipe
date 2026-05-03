import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Recipe grid card — image at top with `prep+cook` overlay, then cuisine,
/// title, and up to two static tag chips. Mirrors `.recipe-card` in the
/// wireframe.
class RecipeCard extends StatefulWidget {
  const RecipeCard({super.key, required this.recipe, required this.onTap});
  final Recipe recipe;
  final VoidCallback onTap;

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final r = widget.recipe;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: RecipeRadius.fieldBR,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: rt.paper2,
                          border: Border.all(color: rt.hair),
                          borderRadius: RecipeRadius.fieldBR,
                        ),
                        child: r.image.isEmpty
                            ? null
                            : Image.network(
                                r.image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                              ),
                      ),
                      Positioned(
                        top: 10, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: rt.imgTint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${r.totalTime} min',
                            style: RecipeTypography.mono(size: 10.5, weight: FontWeight.w400, color: rt.ink, letterSpacing: 0.42),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                r.title,
                style: RecipeTypography.serif(size: 19, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.19, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
