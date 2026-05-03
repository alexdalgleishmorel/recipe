import 'package:flutter/material.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../utils/id_gen.dart';
import '../widgets/buttons.dart';
import '../widgets/dropzone.dart';
import '../widgets/ingredient_editor.dart';
import '../widgets/instruction_editor.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';

enum _UploadStage { empty, parsing, review }

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, required this.recipesRepo, required this.onChanged});
  final RecipesRepository recipesRepo;
  final Future<void> Function() onChanged;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  _UploadStage _stage = _UploadStage.empty;
  String _filename = '';
  Recipe _draft = Recipe.blank('staging');

  void _onFile(String name) {
    setState(() {
      _filename = name;
      _stage = _UploadStage.parsing;
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() {
        _stage = _UploadStage.review;
        _draft = _demoRecipe();
      });
    });
  }

  void _scratch() {
    setState(() {
      _filename = '';
      _stage = _UploadStage.review;
      _draft = Recipe.blank(newId('r'));
    });
  }

  Future<void> _save() async {
    if (_draft.title.trim().isEmpty) {
      showToast(context, 'Give your recipe a title first');
      return;
    }
    final final_ = _draft.copyWith(id: newId('r'));
    await widget.recipesRepo.save(final_);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Saved to library');
    setState(() {
      _stage = _UploadStage.empty;
      _filename = '';
      _draft = Recipe.blank('staging');
    });
  }

  void _discard() {
    setState(() {
      _stage = _UploadStage.empty;
      _filename = '';
      _draft = Recipe.blank('staging');
    });
  }

  Recipe _demoRecipe() => Recipe(
        id: 'staging',
        title: "Mom's Sunday Lasagna",
        cuisine: 'Italian',
        image: '',
        description:
            'A bolognese lasagna with fresh pasta sheets, slow-cooked sauce, and a creamy béchamel. Best made the day before.',
        prepTime: 30,
        cookTime: 90,
        servings: 8,
        tags: const ['family', 'sunday'],
        dietary: const [],
        author: 'Me',
        customTags: const [],
        ingredients: const [
          Ingredient(amount: '1', unit: 'lb', name: 'fresh lasagna sheets'),
          Ingredient(amount: '2', unit: 'lb', name: 'ground beef + pork mix'),
          Ingredient(amount: '1', unit: 'qt', name: 'whole tomatoes'),
          Ingredient(amount: '1', unit: 'cup', name: 'béchamel'),
          Ingredient(amount: '300', unit: 'g', name: 'mozzarella'),
        ],
        instructions: const [
          'Brown the meat in olive oil with a soffritto until deeply colored.',
          'Add tomatoes; simmer 90 minutes until thick.',
          'Make the béchamel; season with nutmeg.',
          'Layer pasta, sauce, béchamel, and mozzarella in a deep dish.',
          'Bake at 375°F for 35 minutes; rest 15 before slicing.',
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ContentScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHead(
            title: 'Upload',
            subtitle: 'Drop a file, paste a URL, or write one from scratch',
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_stage),
              child: switch (_stage) {
                _UploadStage.empty => _emptyBox(),
                _UploadStage.parsing => _parsingBox(),
                _UploadStage.review => _reviewBox(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateBlock({required String title, required String desc, required Widget child}) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(
            color: rt.paper2,
            border: Border(bottom: BorderSide(color: rt.hair)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Row(children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: rt.ink)),
            const Spacer(),
            Text(desc,
                style: RecipeTypography.mono(size: 13, color: rt.ink3, letterSpacing: 0.26)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(32), child: child),
      ]),
    );
  }

  Widget _emptyBox() {
    final rt = context.rt;
    return _stateBlock(
      title: 'Add a recipe',
      desc: 'no file selected',
      child: Column(children: [
        Dropzone(onFile: _onFile),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Container(height: 1, color: rt.hair)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('OR', style: RecipeTypography.mono(size: 10, color: rt.ink3, letterSpacing: 1.4)),
          ),
          Expanded(child: Container(height: 1, color: rt.hair)),
        ]),
        const SizedBox(height: 18),
        Center(
          child: Btn(
            label: 'Start from scratch',
            icon: Icons.edit_outlined,
            onPressed: _scratch,
          ),
        ),
      ]),
    );
  }

  Widget _parsingBox() {
    final rt = context.rt;
    return _stateBlock(
      title: 'Parsing',
      desc: 'extracting fields',
      child: Container(
        decoration: BoxDecoration(
          color: rt.paper2,
          border: Border.all(color: rt.hair),
          borderRadius: RecipeRadius.fieldBR,
        ),
        padding: const EdgeInsets.all(24),
        child: Row(children: [
          SizedBox(
            width: 32, height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: rt.accent, backgroundColor: rt.hair2),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_filename,
                  style: TextStyle(fontWeight: FontWeight.w500, color: rt.ink)),
              const SizedBox(height: 2),
              Text('Vision pass · 62%',
                  style: RecipeTypography.mono(size: 13, color: rt.ink3, letterSpacing: 0)),
            ]),
          ),
          Btn(label: 'Cancel', size: BtnSize.sm, onPressed: _discard),
        ]),
      ),
    );
  }

  Widget _reviewBox() => _stateBlock(
        title: 'Review & save',
        desc: 'editable fields',
        child: _ReviewForm(
          draft: _draft,
          onChange: (r) => setState(() => _draft = r),
          onSave: _save,
          onDiscard: _discard,
        ),
      );
}

class _ReviewForm extends StatelessWidget {
  const _ReviewForm({required this.draft, required this.onChange, required this.onSave, required this.onDiscard});
  final Recipe draft;
  final ValueChanged<Recipe> onChange;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: rt.ink3),
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.accent)),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 14),
          child: Text(text.toUpperCase(),
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.66)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      label('Title'),
      TextFormField(
        initialValue: draft.title,
        decoration: dec('Recipe title'),
        onChanged: (v) => onChange(draft.copyWith(title: v)),
      ),
      label('Description'),
      TextFormField(
        initialValue: draft.description,
        minLines: 3, maxLines: 6,
        decoration: dec('Short description'),
        onChanged: (v) => onChange(draft.copyWith(description: v)),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('Prep (min)'),
            TextFormField(
              initialValue: draft.prepTime.toString(),
              keyboardType: TextInputType.number,
              decoration: dec('0'),
              onChanged: (v) => onChange(draft.copyWith(prepTime: int.tryParse(v) ?? 0)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('Cook (min)'),
            TextFormField(
              initialValue: draft.cookTime.toString(),
              keyboardType: TextInputType.number,
              decoration: dec('0'),
              onChanged: (v) => onChange(draft.copyWith(cookTime: int.tryParse(v) ?? 0)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('Servings'),
            TextFormField(
              initialValue: draft.servings.toString(),
              keyboardType: TextInputType.number,
              decoration: dec('1'),
              onChanged: (v) => onChange(draft.copyWith(servings: int.tryParse(v) ?? 1)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('Cuisine'),
            TextFormField(
              initialValue: draft.cuisine,
              decoration: dec('e.g. Italian'),
              onChanged: (v) => onChange(draft.copyWith(cuisine: v)),
            ),
          ]),
        ),
      ]),
      label('Ingredients'),
      IngredientEditor(
        ingredients: draft.ingredients,
        onChanged: (list) => onChange(draft.copyWith(ingredients: list)),
      ),
      label('Instructions'),
      InstructionEditor(
        steps: draft.instructions,
        onChanged: (list) => onChange(draft.copyWith(instructions: list)),
      ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Btn(label: 'Discard', variant: BtnVariant.danger, onPressed: onDiscard),
        const SizedBox(width: 8),
        Btn(label: 'Save to library', variant: BtnVariant.primary, icon: Icons.check, onPressed: onSave),
      ]),
    ]);
  }
}
