import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_theme.dart';
import '../modal_shell.dart';

/// Generic recipe picker, used both for assigning a recipe to a calendar cell
/// and for adding a new candidate. Optionally pins a `candidates` list to the
/// top.
Future<Recipe?> openRecipePicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Recipe> recipes,
  List<String> candidateIds = const [],
  String? currentRecipeId,
}) {
  return showRecipeModal<Recipe>(
    context: context,
    builder: (ctx) => _RecipePickerBody(
      title: title,
      subtitle: subtitle,
      recipes: recipes,
      candidateIds: candidateIds,
      currentRecipeId: currentRecipeId,
    ),
  );
}

class _RecipePickerBody extends StatefulWidget {
  const _RecipePickerBody({
    required this.title,
    required this.subtitle,
    required this.recipes,
    required this.candidateIds,
    required this.currentRecipeId,
  });
  final String title;
  final String? subtitle;
  final List<Recipe> recipes;
  final List<String> candidateIds;
  final String? currentRecipeId;
  @override
  State<_RecipePickerBody> createState() => _RecipePickerBodyState();
}

class _RecipePickerBodyState extends State<_RecipePickerBody> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final q = _q.toLowerCase();
    final candidates = widget.recipes
        .where((r) => widget.candidateIds.contains(r.id))
        .where((r) => q.isEmpty || r.title.toLowerCase().contains(q) || r.cuisine.toLowerCase().contains(q))
        .toList();
    final others = widget.recipes
        .where((r) => !widget.candidateIds.contains(r.id))
        .where((r) => q.isEmpty || r.title.toLowerCase().contains(q) || r.cuisine.toLowerCase().contains(q))
        .toList();

    return ModalShell(
      title: widget.title,
      subtitle: widget.subtitle,
      maxWidth: 540,
      actions: [const CancelButton()],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Search recipes',
            hintStyle: TextStyle(color: rt.ink3),
            prefixIcon: Icon(Icons.search, size: 18, color: rt.ink3),
            isDense: true,
            border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
            enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
            focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.accent)),
          ),
        ),
        const SizedBox(height: 14),
        if (candidates.isNotEmpty) ...[
          _SecLabel('Candidates'),
          const SizedBox(height: 6),
          for (final r in candidates) _Row(recipe: r, current: r.id == widget.currentRecipeId),
          const SizedBox(height: 12),
          _SecLabel('All recipes'),
          const SizedBox(height: 6),
        ],
        if (others.isEmpty && candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No matches.', style: TextStyle(color: rt.ink3)),
          ),
        for (final r in others) _Row(recipe: r, current: r.id == widget.currentRecipeId),
      ]),
    );
  }
}

class _SecLabel extends StatelessWidget {
  const _SecLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: RecipeTypography.mono(size: 10.5, color: context.rt.ink3, letterSpacing: 0.84));
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.recipe, required this.current});
  final Recipe recipe;
  final bool current;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).pop(recipe),
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: current ? rt.accentSoft : rt.paper,
            border: Border.all(color: current ? rt.accent : rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: rt.paper2,
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
                  Text(recipe.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: rt.ink)),
                  Text('${recipe.cuisine} · ${recipe.totalTime} min',
                      style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0)),
                ],
              ),
            ),
            if (current) Icon(Icons.check, size: 16, color: rt.accent),
          ]),
        ),
      ),
    );
  }
}
