import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/custom_tag.dart';
import '../models/ingredient.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/ingredient_editor.dart';
import '../widgets/instruction_editor.dart';
import '../widgets/modals/add_to_collection_modal.dart';
import '../widgets/modals/add_to_plan_modal.dart';
import '../widgets/modals/delete_recipe_modal.dart';
import '../widgets/page_head.dart';
import '../widgets/tag_chip.dart';
import '../widgets/toast.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.recipeId,
    required this.recipesRepo,
    required this.plansRepo,
    required this.plans,
    required this.onChanged,
    this.collectionsRepo,
    this.collections = const [],
    this.startInEditMode = false,
  });

  final String recipeId;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final List<MealPlan> plans;
  final Future<void> Function() onChanged;
  final CollectionsRepository? collectionsRepo;
  final List<Collection> collections;
  final bool startInEditMode;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Recipe? _recipe;
  bool _editing = false;
  bool _loading = true;

  // Working draft when editing.
  Recipe? _draft;

  @override
  void initState() {
    super.initState();
    _editing = widget.startInEditMode;
    _load();
  }

  Future<void> _load() async {
    final r = await widget.recipesRepo.get(widget.recipeId);
    if (!mounted) return;
    setState(() {
      _recipe = r;
      _draft = r;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_draft == null) return;
    await widget.recipesRepo.save(_draft!);
    await widget.onChanged();
    if (!mounted) return;
    setState(() {
      _recipe = _draft;
      _editing = false;
    });
    showToast(context, 'Saved');
  }

  Future<void> _delete() async {
    final r = _recipe;
    if (r == null) return;
    final ok = await openDeleteRecipeModal(context, r);
    if (!ok) return;
    await widget.recipesRepo.delete(r.id);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Recipe deleted');
    Navigator.of(context).pop();
  }

  Future<void> _addToPlan() async {
    final r = _recipe;
    if (r == null) return;
    final result = await openAddToPlanModal(context, recipe: r, plans: widget.plans);
    if (result == null) return;
    await widget.plansRepo.save(result.plan);
    await widget.onChanged();
    if (!mounted) return;
    showToast(
      context,
      result.created
          ? 'New draft created with ${r.title}'
          : 'Added to ${result.plan.displayName}',
    );
  }

  Future<void> _addToCollection() async {
    final r = _recipe;
    final repo = widget.collectionsRepo;
    if (r == null || repo == null) return;
    final result = await openAddToCollectionModal(context, recipe: r, collections: widget.collections);
    if (result == null) return;
    if (result.alreadyPresent) {
      if (!mounted) return;
      showToast(context, 'Already in ${result.collection.name}');
      return;
    }
    await repo.save(result.collection);
    await widget.onChanged();
    if (!mounted) return;
    showToast(
      context,
      result.created
          ? 'Created ${result.collection.name} with ${r.title}'
          : 'Added to ${result.collection.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (_loading) {
      return Scaffold(backgroundColor: rt.paper, body: const Center(child: CircularProgressIndicator()));
    }
    final r = _recipe;
    if (r == null) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(child: Text('Recipe not found.', style: TextStyle(color: rt.ink3))),
      );
    }

    return Scaffold(
      backgroundColor: rt.paper,
      body: ContentScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _back(context),
            const SizedBox(height: 12),
            if (_editing) _editBanner(),
            _hero(r),
            const SizedBox(height: 28),
            _metaRow(r),
            const SizedBox(height: 28),
            _tagsBlock(r),
            const SizedBox(height: 24),
            if (!_editing) _actions(r),
            const SizedBox(height: 32),
            _body(r),
          ],
        ),
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

  Widget _editBanner() {
    final rt = context.rt;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: rt.accentSoft,
        border: Border.all(color: rt.accent.withValues(alpha: 0.3)),
        borderRadius: RecipeRadius.fieldBR,
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            'Editing recipe — your changes will save to local storage.',
            style: TextStyle(color: rt.accentInk, fontSize: 13.5),
          ),
        ),
        Btn(label: 'Cancel', size: BtnSize.sm, onPressed: () => setState(() {
              _draft = _recipe;
              _editing = false;
            })),
        const SizedBox(width: 8),
        Btn(label: 'Save', size: BtnSize.sm, variant: BtnVariant.primary, onPressed: _save),
      ]),
    );
  }

  Widget _hero(Recipe r) {
    final rt = context.rt;
    return LayoutBuilder(builder: (ctx, c) {
      final isDesktop = c.maxWidth >= 760;
      final image = AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: RecipeRadius.cardBR,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: rt.hair),
              borderRadius: RecipeRadius.cardBR,
              color: rt.paper2,
            ),
            child: r.image.isEmpty
                ? null
                : Image.network(r.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        ),
      );

      final right = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing)
            _titleField(_draft!.title, (v) => setState(() => _draft = _draft!.copyWith(title: v)))
          else
            Text(r.title,
                style: RecipeTypography.serif(size: 48, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.96, height: 1.05)),
          const SizedBox(height: 14),
          if (_editing)
            _multiField(_draft!.description, (v) => setState(() => _draft = _draft!.copyWith(description: v)))
          else
            Text(r.description, style: TextStyle(color: rt.ink2, fontSize: 16.5, height: 1.55)),
        ],
      );

      if (isDesktop) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 12, child: image),
            const SizedBox(width: 48),
            Expanded(flex: 10, child: right),
          ],
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [image, const SizedBox(height: 24), right]);
    });
  }

  Widget _titleField(String value, ValueChanged<String> onChanged) {
    final rt = context.rt;
    return TextField(
      controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      style: RecipeTypography.serif(size: 48, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.96, height: 1.05),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.hair2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.hair2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.accent)),
      ),
    );
  }

  Widget _multiField(String value, ValueChanged<String> onChanged) {
    final rt = context.rt;
    return TextField(
      controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      minLines: 3, maxLines: 8,
      style: TextStyle(fontSize: 16.5, color: rt.ink2, height: 1.55),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.hair2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.hair2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: rt.accent)),
      ),
    );
  }

  Widget _metaRow(Recipe r) {
    final rt = context.rt;
    final entries = [
      ('PREP', '${r.prepTime} min', (int v) => _draft = _draft!.copyWith(prepTime: v)),
      ('COOK', '${r.cookTime} min', (int v) => _draft = _draft!.copyWith(cookTime: v)),
      ('SERVES', '${r.servings}', (int v) => _draft = _draft!.copyWith(servings: v)),
      ('CUISINE', r.cuisine, null),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: rt.hair),
          bottom: BorderSide(color: rt.hair),
        ),
      ),
      child: Row(children: [
        for (var i = 0; i < entries.length; i++) ...[
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 16, 14, 16, 14),
              decoration: BoxDecoration(
                border: Border(
                  right: i < entries.length - 1 ? BorderSide(color: rt.hair) : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entries[i].$1,
                      style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
                  const SizedBox(height: 4),
                  Text(entries[i].$2,
                      style: RecipeTypography.serif(size: 17, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.17)),
                ],
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _tagsBlock(Recipe r) {
    final rt = context.rt;
    final dietaryTags = r.dietary.map((d) => CustomTag(key: 'dietary', value: d)).toList();
    final tagsTags = r.tags.map((t) => CustomTag(key: 'tags', value: t)).toList();
    final all = [...tagsTags, ...dietaryTags, ...r.customTags];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TAGS', style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
        const SizedBox(height: 8),
        if (all.isEmpty)
          Text('No tags',
              style: RecipeTypography.mono(size: 11.5, color: rt.ink3, letterSpacing: 0.46))
        else
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final tag in all)
                KvTagChip(tag: tag, dietary: tag.key == 'dietary'),
            ],
          ),
      ],
    );
  }

  Widget _actions(Recipe r) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      Btn(label: 'Edit', icon: Icons.edit_outlined, onPressed: () => setState(() {
            _draft = r;
            _editing = true;
          })),
      Btn(label: 'Add to meal plan', icon: Icons.calendar_today_outlined, variant: BtnVariant.primary, onPressed: _addToPlan),
      if (widget.collectionsRepo != null)
        Btn(label: 'Add to collection', icon: Icons.folder_outlined, onPressed: _addToCollection),
      Btn(label: 'Delete', icon: Icons.delete_outline, variant: BtnVariant.danger, onPressed: _delete),
    ]);
  }

  Widget _body(Recipe r) {
    final rt = context.rt;
    return LayoutBuilder(builder: (ctx, c) {
      final isDesktop = c.maxWidth >= 760;
      Widget header(String text) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rt.hair))),
              child: Text(text,
                  style: RecipeTypography.serif(size: 24, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.24)),
            ),
          );

      final ingCol = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('Ingredients'),
          if (_editing)
            IngredientEditor(
              ingredients: r.ingredients,
              onChanged: (list) => _draft = _draft!.copyWith(ingredients: list),
            )
          else
            Column(children: [
              for (final ing in r.ingredients) _IngRow(ing: ing),
            ]),
        ],
      );
      final instCol = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('Instructions'),
          if (_editing)
            InstructionEditor(
              steps: r.instructions,
              onChanged: (list) => _draft = _draft!.copyWith(instructions: list),
            )
          else
            Column(children: [
              for (var i = 0; i < r.instructions.length; i++) _StepRow(idx: i + 1, text: r.instructions[i]),
            ]),
        ],
      );

      if (isDesktop) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 1, child: ingCol),
          const SizedBox(width: 64),
          Expanded(flex: 2, child: instCol),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ingCol, const SizedBox(height: 32), instCol,
      ]);
    });
  }
}

class _IngRow extends StatelessWidget {
  const _IngRow({required this.ing});
  final Ingredient ing;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rt.hair, style: BorderStyle.solid))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        SizedBox(
          width: 90,
          child: Text(
            ([ing.amount, ing.unit].where((s) => s.isNotEmpty).join(' ')),
            style: RecipeTypography.mono(size: 13, weight: FontWeight.w500, color: rt.ink2, letterSpacing: 0),
          ),
        ),
        Expanded(child: Text(ing.name, style: TextStyle(fontSize: 15, color: rt.ink))),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.idx, required this.text});
  final int idx;
  final String text;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rt.hair))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(right: 18, top: 1),
          child: Text(
            idx.toString().padLeft(2, '0'),
            style: RecipeTypography.mono(size: 13, weight: FontWeight.w500, color: rt.accentInk, letterSpacing: 0.52),
          ),
        ),
        Expanded(
          child: Text(text, style: TextStyle(color: rt.ink2, fontSize: 15.5, height: 1.6)),
        ),
      ]),
    );
  }
}
