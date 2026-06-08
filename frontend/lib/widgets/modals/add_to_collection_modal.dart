import 'package:flutter/material.dart';

import '../../models/collection.dart';
import '../../models/recipe.dart';
import '../../theme/app_theme.dart';
import '../modal_shell.dart';
import 'collection_form_modal.dart';

class AddToCollectionResult {
  AddToCollectionResult({required this.collection, required this.created, required this.alreadyPresent});
  final Collection collection;
  final bool created;
  final bool alreadyPresent;
}

/// Lists the user's collections so a recipe can be added to one, plus a
/// "create new collection" row. Mirrors [openAddToPlanModal]. The returned
/// collection already contains [recipe]'s id; persist it via the repository.
Future<AddToCollectionResult?> openAddToCollectionModal(
  BuildContext context, {
  required Recipe recipe,
  required List<Collection> collections,
}) async {
  return showRecipeModal<AddToCollectionResult>(
    context: context,
    builder: (ctx) {
      final rt = ctx.rt;
      return ModalShell(
        title: 'Add to a collection',
        subtitle: 'Group "${recipe.title}" with related recipes.',
        actions: [const CancelButton()],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in collections)
              _CollectionRow(
                title: c.name,
                subtitle: '${c.recipeIds.length} recipe${c.recipeIds.length == 1 ? '' : 's'}',
                onTap: () {
                  if (c.recipeIds.contains(recipe.id)) {
                    Navigator.of(ctx, rootNavigator: true).pop(
                      AddToCollectionResult(collection: c, created: false, alreadyPresent: true),
                    );
                    return;
                  }
                  final updated = c.copyWith(recipeIds: [...c.recipeIds, recipe.id]);
                  Navigator.of(ctx, rootNavigator: true).pop(
                    AddToCollectionResult(collection: updated, created: false, alreadyPresent: false),
                  );
                },
              ),
            if (collections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No collections yet. Create one below.',
                  style: TextStyle(color: rt.ink3, fontSize: 13.5),
                ),
              ),
            const SizedBox(height: 12),
            Text('OR', style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
            const SizedBox(height: 6),
            _CollectionRow(
              title: 'Create a new collection',
              subtitle: 'Name it, then add this recipe',
              accent: true,
              onTap: () async {
                final created = await openCollectionFormModal(ctx);
                if (created == null) return;
                final withRecipe = created.copyWith(recipeIds: [recipe.id]);
                if (!ctx.mounted) return;
                Navigator.of(ctx, rootNavigator: true).pop(
                  AddToCollectionResult(collection: withRecipe, created: true, alreadyPresent: false),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.title, required this.subtitle, required this.onTap, this.accent = false});
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent ? Color.alphaBlend(rt.accent.withValues(alpha: 0.06), rt.paper) : rt.paper,
            border: Border.all(color: accent ? rt.accent : rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontWeight: FontWeight.w500, color: accent ? rt.accentInk : rt.ink, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: rt.ink3)),
                  ],
                ),
              ),
              if (accent) Icon(Icons.add, size: 16, color: rt.accentInk),
            ],
          ),
        ),
      ),
    );
  }
}
