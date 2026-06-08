import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../models/share_item.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/modals/collection_form_modal.dart';
import '../widgets/modals/delete_collection_modal.dart';
import '../widgets/modals/recipe_picker_modal.dart';
import '../widgets/modals/share_modal.dart';
import '../widgets/page_head.dart';
import '../widgets/recipe_card.dart';
import '../widgets/toast.dart';
import 'recipe_detail_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.collectionsRepo,
    required this.recipesRepo,
    required this.plansRepo,
    required this.recipes,
    required this.plans,
    required this.onChanged,
    this.sharingRepo,
  });

  final String collectionId;
  final CollectionsRepository collectionsRepo;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final List<Recipe> recipes;
  final List<MealPlan> plans;
  final Future<void> Function() onChanged;
  final SharingRepository? sharingRepo;

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  Collection? _collection;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.collectionsRepo.get(widget.collectionId);
    if (!mounted) return;
    setState(() {
      _collection = c;
      _loading = false;
    });
  }

  Future<void> _rename() async {
    final c = _collection;
    if (c == null) return;
    final updated = await openCollectionFormModal(context, existing: c);
    if (updated == null) return;
    await widget.collectionsRepo.save(updated);
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _collection = updated);
    showToast(context, 'Collection updated');
  }

  Future<void> _delete() async {
    final c = _collection;
    if (c == null) return;
    final ok = await openDeleteCollectionModal(context, c);
    if (!ok) return;
    await widget.collectionsRepo.delete(c.id);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Collection deleted');
    Navigator.of(context).pop();
  }

  Future<void> _addRecipe() async {
    final c = _collection;
    if (c == null) return;
    final available = widget.recipes.where((r) => !c.recipeIds.contains(r.id)).toList();
    if (available.isEmpty) {
      showToast(context, 'Every recipe is already in this collection');
      return;
    }
    final picked = await openRecipePicker(
      context,
      title: 'Add a recipe',
      subtitle: 'Pick a recipe to add to "${c.name}".',
      recipes: available,
    );
    if (picked == null) return;
    final updated = c.copyWith(recipeIds: [...c.recipeIds, picked.id]);
    await widget.collectionsRepo.save(updated);
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _collection = updated);
    showToast(context, 'Added ${picked.title}');
  }

  Future<void> _removeRecipe(Recipe r) async {
    final c = _collection;
    if (c == null) return;
    final updated = c.copyWith(recipeIds: c.recipeIds.where((id) => id != r.id).toList());
    await widget.collectionsRepo.save(updated);
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _collection = updated);
    showToast(context, 'Removed ${r.title}');
  }

  Future<void> _share() async {
    final c = _collection;
    final repo = widget.sharingRepo;
    if (c == null || repo == null) return;
    await openShareModal(
      context,
      item: ShareItem(type: ShareItemType.collection, id: c.id, title: c.name),
      sharingRepo: repo,
    );
  }

  void _openRecipe(Recipe r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(
        recipeId: r.id,
        recipesRepo: widget.recipesRepo,
        plansRepo: widget.plansRepo,
        plans: widget.plans,
        collectionsRepo: widget.collectionsRepo,
        collections: _collection == null ? const [] : [_collection!],
        sharingRepo: widget.sharingRepo,
        onChanged: widget.onChanged,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (_loading) {
      return Scaffold(backgroundColor: rt.paper, body: const Center(child: CircularProgressIndicator()));
    }
    final c = _collection;
    if (c == null) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(child: Text('Collection not found.', style: TextStyle(color: rt.ink3))),
      );
    }

    final byId = {for (final r in widget.recipes) r.id: r};
    final recipes = c.recipeIds.map((id) => byId[id]).whereType<Recipe>().toList();

    return Scaffold(
      backgroundColor: rt.paper,
      body: ContentScroll(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _back(context),
          const SizedBox(height: 12),
          PageHead(
            title: c.name,
            subtitle: c.description.isEmpty
                ? '${recipes.length} recipe${recipes.length == 1 ? '' : 's'}'
                : c.description,
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(label: 'Add recipe', icon: Icons.add, variant: BtnVariant.primary, onPressed: _addRecipe),
            Btn(label: 'Rename', icon: Icons.edit_outlined, onPressed: _rename),
            if (widget.sharingRepo != null)
              Btn(label: 'Share', icon: Icons.ios_share, onPressed: _share),
            Btn(label: 'Delete', icon: Icons.delete_outline, variant: BtnVariant.danger, onPressed: _delete),
          ]),
          const SizedBox(height: 28),
          if (recipes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No recipes yet — add one to build this collection.',
                style: TextStyle(color: rt.ink3, fontSize: 14),
              ),
            )
          else
            LayoutBuilder(builder: (ctx, lc) {
              final cols = lc.maxWidth < 900 ? 2 : (lc.maxWidth < 1280 ? 3 : 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recipes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (_, i) {
                  final r = recipes[i];
                  return Stack(children: [
                    RecipeCard(recipe: r, onTap: () => _openRecipe(r)),
                    Positioned(
                      top: 8, right: 8,
                      child: _RemoveButton(onTap: () => _removeRecipe(r)),
                    ),
                  ]);
                },
              );
            }),
        ]),
      ),
    );
  }

  Widget _back(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_back, size: 14, color: rt.ink3),
          const SizedBox(width: 6),
          Text('BACK', style: RecipeTypography.mono(size: 13, color: rt.ink3, letterSpacing: 0.52)),
        ]),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Material(
      color: rt.imgTint,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(Icons.close, size: 15, color: rt.ink),
        ),
      ),
    );
  }
}
