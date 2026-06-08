import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../models/user.dart';
import '../services/http_recipe_import_service.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../utils/id_gen.dart';
import '../utils/web_download.dart';
import '../widgets/buttons.dart';
import '../widgets/dropzone.dart';
import '../widgets/ingredient_editor.dart';
import '../widgets/instruction_editor.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';

/// The repo-relative docs page describing the JSON import schema.
const _schemaDocsUrl =
    'https://github.com/alexdalgleishmorel/recipes/blob/main/docs/recipe-import-schema.md';

/// The exact example template shown in the JSON helper and offered for download.
const _exampleJson = '''{
  "title": "Weeknight Tomato Pasta",
  "cuisine": "Italian",
  "description": "A fast pantry pasta.",
  "prepTime": 10,
  "cookTime": 20,
  "servings": 4,
  "tags": ["weeknight", "vegetarian"],
  "dietary": ["vegetarian"],
  "author": "Me",
  "ingredients": [
    {"amount": "400", "unit": "g", "name": "spaghetti"},
    {"amount": "1", "unit": "can", "name": "crushed tomatoes"}
  ],
  "instructions": ["Boil the pasta until al dente.", "Simmer the tomatoes, toss with the pasta, and serve."]
}''';

enum _UploadStage { empty, parsing, review }

/// One row in the review list: either a successful, editable [draft] (which
/// may be [saved]), or a failed parse carrying its [error]. The `manual` flag
/// marks the "Start from scratch" entry so its header reads differently.
class _ReviewEntry {
  _ReviewEntry({
    required this.filename,
    this.draft,
    this.error,
    this.tier,
    this.manual = false,
  }) : key = newId('entry');

  final String key;
  final String filename;
  Recipe? draft;
  final String? error;
  final String? tier;
  final bool manual;
  bool saved = false;

  bool get ok => draft != null;
  bool get savable => ok && !saved;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({
    super.key,
    required this.user,
    required this.recipesRepo,
    required this.importService,
    required this.onChanged,
  });

  final User user;
  final RecipesRepository recipesRepo;
  final RecipeImportService importService;
  final Future<void> Function() onChanged;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  _UploadStage _stage = _UploadStage.empty;
  List<_ReviewEntry> _entries = [];
  int _parsingCount = 0;

  Future<void> _onFiles(List<PickedFile> files) async {
    if (files.isEmpty) return;
    setState(() {
      _parsingCount = files.length;
      _stage = _UploadStage.parsing;
    });
    try {
      final results = await widget.importService.parseAll([
        for (final f in files)
          RecipeImportFile(
            bytes: f.bytes,
            filename: f.filename,
            contentType: contentTypeForFilename(f.filename),
          ),
      ]);
      if (!mounted) return;
      setState(() {
        _stage = _UploadStage.review;
        _entries = [
          for (final r in results)
            _ReviewEntry(
              filename: r.filename,
              draft: r.draft,
              error: r.error,
              tier: r.tier,
            ),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UploadStage.empty;
        _entries = [];
      });
      final message = e is RecipeImportException
          ? e.message
          : 'Could not parse those files';
      showToast(context, message);
    }
  }

  void _scratch() {
    setState(() {
      _stage = _UploadStage.review;
      _entries = [
        _ReviewEntry(
          filename: 'New recipe',
          draft: Recipe.blank('staging'),
          manual: true,
        ),
      ];
    });
  }

  Future<void> _saveEntry(_ReviewEntry entry) async {
    final draft = entry.draft;
    if (draft == null) return;
    if (draft.title.trim().isEmpty) {
      showToast(context, 'Give "${entry.filename}" a title first');
      return;
    }
    await widget.recipesRepo.save(draft.copyWith(id: newId('r')));
    await widget.onChanged();
    if (!mounted) return;
    setState(() => entry.saved = true);
    showToast(context, 'Saved to library');
  }

  Future<void> _saveAll() async {
    final pending = _entries.where((e) => e.savable).toList();
    if (pending.isEmpty) return;
    var savedCount = 0;
    for (final entry in pending) {
      final draft = entry.draft;
      if (draft == null || draft.title.trim().isEmpty) continue;
      await widget.recipesRepo.save(draft.copyWith(id: newId('r')));
      entry.saved = true;
      savedCount++;
    }
    await widget.onChanged();
    if (!mounted) return;
    setState(() {});
    if (savedCount == 0) {
      showToast(context, 'Give your recipes a title first');
    } else {
      showToast(context, 'Saved $savedCount to library');
    }
  }

  void _removeEntry(_ReviewEntry entry) {
    setState(() {
      _entries.remove(entry);
      if (_entries.isEmpty) _stage = _UploadStage.empty;
    });
  }

  void _reset() {
    setState(() {
      _stage = _UploadStage.empty;
      _entries = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead(
            title: 'Upload',
            subtitle: widget.user.canAiImport
                ? 'Drop one or many files to import, or write one from scratch'
                : 'Write a recipe from scratch',
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

  Widget _stateBlock({
    required String title,
    required String desc,
    required Widget child,
  }) {
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
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 15, color: rt.ink)),
            const Spacer(),
            Text(desc,
                style: RecipeTypography.mono(
                    size: 13, color: rt.ink3, letterSpacing: 0.26)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(32), child: child),
      ]),
    );
  }

  Widget _emptyBox() {
    final rt = context.rt;
    final canAi = widget.user.canAiImport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stateBlock(
          title: 'Add recipes',
          desc: canAi ? 'no files selected' : 'manual entry',
          child: Column(children: [
            if (canAi) ...[
              Dropzone(onFiles: _onFiles),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Container(height: 1, color: rt.hair)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('OR',
                      style: RecipeTypography.mono(
                          size: 10, color: rt.ink3, letterSpacing: 1.4)),
                ),
                Expanded(child: Container(height: 1, color: rt.hair)),
              ]),
              const SizedBox(height: 18),
            ],
            Center(
              child: Btn(
                label: 'Start from scratch',
                icon: Icons.edit_outlined,
                onPressed: _scratch,
              ),
            ),
            if (!canAi) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 14, color: rt.ink3),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'AI import is admin-enabled — write your recipe by hand for now.',
                      textAlign: TextAlign.center,
                      style: RecipeTypography.mono(
                          size: 11, color: rt.ink3, letterSpacing: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ]),
        ),
        if (canAi) ...[
          const SizedBox(height: 16),
          const _JsonHelper(),
        ],
      ],
    );
  }

  Widget _parsingBox() {
    final rt = context.rt;
    final n = _parsingCount;
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
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: rt.accent, backgroundColor: rt.hair2),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 1 ? 'Parsing 1 file' : 'Parsing $n files',
                    style:
                        TextStyle(fontWeight: FontWeight.w500, color: rt.ink),
                  ),
                  const SizedBox(height: 2),
                  Text('Extracting recipes',
                      style: RecipeTypography.mono(
                          size: 13, color: rt.ink3, letterSpacing: 0)),
                ]),
          ),
          Btn(label: 'Cancel', size: BtnSize.sm, onPressed: _reset),
        ]),
      ),
    );
  }

  Widget _reviewBox() {
    final total = _entries.length;
    final ok = _entries.where((e) => e.ok).length;
    final failed = total - ok;
    final pending = _entries.where((e) => e.savable).length;
    final descParts = <String>[
      if (ok > 0) '$ok ready',
      if (failed > 0) '$failed failed',
    ];
    return _stateBlock(
      title: total == 1 ? 'Review & save' : 'Review & save ($total)',
      desc: descParts.isEmpty ? 'editable fields' : descParts.join(' · '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _ReviewCard(
              key: ValueKey(_entries[i].key),
              entry: _entries[i],
              single: total == 1,
              onChange: (r) => setState(() => _entries[i].draft = r),
              onSave: () => _saveEntry(_entries[i]),
              onRemove: () => _removeEntry(_entries[i]),
            ),
          ],
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Btn(label: 'Done', onPressed: _reset),
            const SizedBox(width: 8),
            Btn(
              label: pending > 1 ? 'Save all ($pending)' : 'Save all',
              variant: BtnVariant.primary,
              icon: Icons.done_all,
              onPressed: pending > 0 ? _saveAll : null,
            ),
          ]),
        ],
      ),
    );
  }
}

/// One card in the review list — a success draft (collapsible, with its own
/// Save) or a failure (filename + error).
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    super.key,
    required this.entry,
    required this.single,
    required this.onChange,
    required this.onSave,
    required this.onRemove,
  });

  final _ReviewEntry entry;
  final bool single;
  final ValueChanged<Recipe> onChange;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late bool _expanded = widget.single || widget.entry.ok;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final entry = widget.entry;
    final title = entry.draft?.title.trim();
    final headTitle = (title != null && title.isNotEmpty)
        ? title
        : (entry.manual ? 'New recipe' : entry.filename);

    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (!entry.ok) {
      statusColor = rt.danger;
      statusIcon = Icons.error_outline;
      statusText = 'failed';
    } else if (entry.saved) {
      statusColor = rt.ok;
      statusIcon = Icons.check_circle_outline;
      statusText = 'saved';
    } else {
      statusColor = rt.ink3;
      statusIcon = Icons.description_outlined;
      statusText = entry.tier ?? 'ready';
    }

    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair2),
        borderRadius: RecipeRadius.fieldBR,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: entry.ok ? () => setState(() => _expanded = !_expanded) : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              color: rt.paper2,
              child: Row(children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14.5,
                              color: rt.ink)),
                      if (!entry.manual) ...[
                        const SizedBox(height: 2),
                        Text(entry.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RecipeTypography.mono(
                                size: 11, color: rt.ink3, letterSpacing: 0.3)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(statusText.toUpperCase(),
                    style: RecipeTypography.mono(
                        size: 10.5, color: statusColor, letterSpacing: 0.7)),
                if (entry.ok) ...[
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: rt.ink3),
                ],
              ]),
            ),
          ),
          if (!entry.ok)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.error ?? 'Could not parse this file.',
                      style: TextStyle(color: rt.ink2, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Btn(
                    label: 'Dismiss',
                    size: BtnSize.sm,
                    onPressed: widget.onRemove,
                  ),
                ],
              ),
            )
          else if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: _ReviewForm(
                draft: entry.draft!,
                saved: entry.saved,
                onChange: widget.onChange,
                onSave: widget.onSave,
                onRemove: widget.onRemove,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewForm extends StatelessWidget {
  const _ReviewForm({
    required this.draft,
    required this.saved,
    required this.onChange,
    required this.onSave,
    required this.onRemove,
  });
  final Recipe draft;
  final bool saved;
  final ValueChanged<Recipe> onChange;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: rt.ink3),
          isCollapsed: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: OutlineInputBorder(
              borderRadius: RecipeRadius.fieldBR,
              borderSide: BorderSide(color: rt.hair2)),
          enabledBorder: OutlineInputBorder(
              borderRadius: RecipeRadius.fieldBR,
              borderSide: BorderSide(color: rt.hair2)),
          focusedBorder: OutlineInputBorder(
              borderRadius: RecipeRadius.fieldBR,
              borderSide: BorderSide(color: rt.accent)),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 14),
          child: Text(text.toUpperCase(),
              style: RecipeTypography.mono(
                  size: 11, color: rt.ink3, letterSpacing: 0.66)),
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
        minLines: 3,
        maxLines: 6,
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
              onChanged: (v) =>
                  onChange(draft.copyWith(prepTime: int.tryParse(v) ?? 0)),
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
              onChanged: (v) =>
                  onChange(draft.copyWith(cookTime: int.tryParse(v) ?? 0)),
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
              onChanged: (v) =>
                  onChange(draft.copyWith(servings: int.tryParse(v) ?? 1)),
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
        Btn(
            label: 'Discard',
            variant: BtnVariant.danger,
            onPressed: onRemove),
        const SizedBox(width: 8),
        Btn(
          label: saved ? 'Saved' : 'Save to library',
          variant: BtnVariant.primary,
          icon: saved ? Icons.check_circle : Icons.check,
          onPressed: saved ? null : onSave,
        ),
      ]),
    ]);
  }
}

/// Collapsible "Uploading JSON?" helper: the expected shape, a Download
/// example.json button, and a link to the schema docs.
class _JsonHelper extends StatefulWidget {
  const _JsonHelper();

  @override
  State<_JsonHelper> createState() => _JsonHelperState();
}

class _JsonHelperState extends State<_JsonHelper> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(children: [
                Icon(Icons.data_object, size: 16, color: rt.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Uploading JSON?',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14.5,
                          color: rt.ink)),
                ),
                Text('expected shape',
                    style: RecipeTypography.mono(
                        size: 11, color: rt.ink3, letterSpacing: 0.5)),
                const SizedBox(width: 8),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: rt.ink3),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload a .json file matching the shape below to import a '
                    'recipe directly — no AI pass. All fields are required; '
                    'do not include id or image. Off-schema files are rejected '
                    'with an error.',
                    style: TextStyle(color: rt.ink2, fontSize: 13.5, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: rt.paper2,
                      border: Border.all(color: rt.hair2),
                      borderRadius: RecipeRadius.fieldBR,
                    ),
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      _exampleJson,
                      style: RecipeTypography.mono(
                          size: 12, color: rt.ink2, letterSpacing: 0),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Btn(
                        label: 'Download example.json',
                        icon: Icons.download_outlined,
                        size: BtnSize.sm,
                        onPressed: () => downloadText(
                          _exampleJson,
                          'example.json',
                          mimeType: 'application/json',
                        ),
                      ),
                      Btn(
                        label: 'View schema docs',
                        icon: Icons.open_in_new,
                        variant: BtnVariant.ghost,
                        size: BtnSize.sm,
                        onPressed: () => openUrl(_schemaDocsUrl),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
