import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

class CandidatesPanel extends StatelessWidget {
  const CandidatesPanel({
    super.key,
    required this.candidates,
    required this.onAdd,
    required this.onTapRecipe,
    required this.onRemove,
    this.readOnly = false,
  });

  final List<Recipe> candidates;
  final VoidCallback onAdd;
  final ValueChanged<Recipe> onTapRecipe;
  final ValueChanged<String> onRemove;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('Candidates',
              style: RecipeTypography.serif(size: 17, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.17)),
          const SizedBox(width: 8),
          Text('${candidates.length} flagged',
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.44)),
          const Spacer(),
          if (!readOnly)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(99),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(border: Border.all(color: rt.hair2), shape: BoxShape.circle),
                child: Icon(Icons.add, size: 14, color: rt.ink3),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No candidates yet — add a few to seed the calendar.',
              style: TextStyle(color: rt.ink3, fontSize: 13),
            ),
          )
        else
          for (final r in candidates) _CandRow(
            recipe: r,
            onTap: () => onTapRecipe(r),
            onRemove: readOnly ? null : () => onRemove(r.id),
          ),
      ]),
    );
  }
}

class _CandRow extends StatelessWidget {
  const _CandRow({required this.recipe, required this.onTap, required this.onRemove});
  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: rt.paper2,
            border: Border.all(color: rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: rt.paper,
                border: Border.all(color: rt.hair),
                borderRadius: BorderRadius.circular(4),
                image: recipe.image.isEmpty
                    ? null
                    : DecorationImage(image: NetworkImage(recipe.image), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.title,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: rt.ink),
                      overflow: TextOverflow.ellipsis),
                  Text(recipe.cuisine.toUpperCase(),
                      style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.63)),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: Icon(Icons.close, size: 14, color: rt.ink3),
              ),
          ]),
        ),
      ),
    );
  }
}
