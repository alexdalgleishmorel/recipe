import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/modals/collection_form_modal.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';
import 'collection_detail_screen.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({
    super.key,
    required this.collections,
    required this.recipes,
    required this.plans,
    required this.collectionsRepo,
    required this.recipesRepo,
    required this.plansRepo,
    required this.sharingRepo,
    required this.onChanged,
  });

  final List<Collection> collections;
  final List<Recipe> recipes;
  final List<MealPlan> plans;
  final CollectionsRepository collectionsRepo;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final SharingRepository sharingRepo;
  final Future<void> Function() onChanged;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  String _query = '';

  Future<void> _newCollection() async {
    final created = await openCollectionFormModal(context);
    if (created == null) return;
    await widget.collectionsRepo.save(created);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Collection created');
    _open(created.id);
  }

  void _open(String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CollectionDetailScreen(
        collectionId: id,
        collectionsRepo: widget.collectionsRepo,
        recipesRepo: widget.recipesRepo,
        plansRepo: widget.plansRepo,
        recipes: widget.recipes,
        plans: widget.plans,
        sharingRepo: widget.sharingRepo,
        onChanged: widget.onChanged,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final q = _query.trim().toLowerCase();
    final list = widget.collections.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) || c.description.toLowerCase().contains(q);
    }).toList();

    return ContentScroll(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead(
          title: 'Collections',
          subtitle: 'Group recipes into named sets you can revisit',
          trailing: Btn(
            label: 'New collection',
            icon: Icons.add,
            variant: BtnVariant.primary,
            onPressed: _newCollection,
          ),
        ),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search collections',
            hintStyle: TextStyle(color: rt.ink3),
            prefixIcon: Icon(Icons.search, size: 18, color: rt.ink3),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.hair)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.hair)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.accent)),
          ),
        ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              widget.collections.isEmpty
                  ? 'No collections yet — create one to get started.'
                  : 'No matches.',
              style: TextStyle(color: rt.ink3, fontSize: 14),
            ),
          )
        else
          Column(
            children: [
              for (final c in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CollectionCard(
                    collection: c,
                    onTap: () => _open(c.id),
                  ),
                ),
            ],
          ),
      ]),
    );
  }
}

class _CollectionCard extends StatefulWidget {
  const _CollectionCard({required this.collection, required this.onTap});
  final Collection collection;
  final VoidCallback onTap;
  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final c = widget.collection;
    final count = c.recipeIds.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: rt.paper,
            border: Border.all(color: _hover ? rt.ink3 : rt.hair),
            borderRadius: RecipeRadius.cardBR,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: RecipeTypography.serif(size: 20, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.2)),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: rt.ink2, height: 1.4)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text('$count recipe${count == 1 ? '' : 's'}',
                style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0.48)),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right, size: 18, color: rt.ink3),
          ]),
        ),
      ),
    );
  }
}
