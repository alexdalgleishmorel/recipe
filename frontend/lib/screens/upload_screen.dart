import 'dart:convert';
import 'dart:typed_data';

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
import '../widgets/photo_field.dart';
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

/// One row in the review list: either a successful, editable [draft] or a
/// failed parse carrying its [error]. The `manual` flag marks the "Start from
/// scratch" entry so its header reads differently. Saving a row removes it from
/// the list, so there's no persisted "saved" state to track.
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

  bool get ok => draft != null;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({
    super.key,
    required this.user,
    required this.recipesRepo,
    required this.importService,
    required this.onChanged,
    this.uploadsRepo,
  });

  final User user;
  final RecipesRepository recipesRepo;
  final RecipeImportService importService;
  final Future<void> Function() onChanged;
  final UploadsRepository? uploadsRepo;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  _UploadStage _stage = _UploadStage.empty;
  List<_ReviewEntry> _entries = [];
  int _parsingCount = 0;

  Future<void> _onFiles(List<PickedFile> files) async {
    if (files.isEmpty) return;
    // JSON imports parse entirely client-side — no AI pass — so they work for
    // every account regardless of the `canAiImport` entitlement. Everything
    // else (images / PDFs) needs the AI import service and is only reachable
    // when the account is entitled.
    final jsonFiles = <PickedFile>[];
    final aiFiles = <PickedFile>[];
    for (final f in files) {
      if (contentTypeForFilename(f.filename) == 'application/json') {
        jsonFiles.add(f);
      } else {
        aiFiles.add(f);
      }
    }

    setState(() {
      _parsingCount = files.length;
      _stage = _UploadStage.parsing;
    });

    final results = <RecipeImportResult>[];
    for (final f in jsonFiles) {
      results.addAll(_parseJsonFile(f.bytes, f.filename));
    }
    if (aiFiles.isNotEmpty) {
      try {
        results.addAll(await widget.importService.parseAll([
          for (final f in aiFiles)
            RecipeImportFile(
              bytes: f.bytes,
              filename: f.filename,
              contentType: contentTypeForFilename(f.filename),
            ),
        ]));
      } catch (e) {
        // Surface the failure per-file so any JSON successes still show.
        final message = e is RecipeImportException
            ? e.message
            : 'Could not parse those files';
        for (final f in aiFiles) {
          results.add(RecipeImportResult(filename: f.filename, error: message));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _stage = results.isEmpty ? _UploadStage.empty : _UploadStage.review;
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
  }

  /// Parse a picked `.json` file client-side into one [RecipeImportResult] per
  /// recipe object (a top-level array imports many at once). Unparseable or
  /// off-schema files yield a failed result rather than throwing.
  List<RecipeImportResult> _parseJsonFile(Uint8List bytes, String filename) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return [
        RecipeImportResult(
          filename: filename,
          error: 'Not valid JSON — check the file and try again.',
        ),
      ];
    }
    final objects = decoded is List ? decoded : [decoded];
    if (objects.isEmpty) {
      return [
        RecipeImportResult(filename: filename, error: 'No recipes in this file.'),
      ];
    }
    return [for (final obj in objects) _jsonObjectToResult(obj, filename)];
  }

  RecipeImportResult _jsonObjectToResult(dynamic obj, String filename) {
    if (obj is! Map<String, dynamic>) {
      return RecipeImportResult(
        filename: filename,
        error: 'Each recipe must be a JSON object — see the expected shape.',
      );
    }
    final title = (obj['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      return RecipeImportResult(
        filename: filename,
        error: 'Missing a "title" — see the expected shape.',
      );
    }
    try {
      // Stamp the staging id the review screen expects and drop any caller
      // `id` / `image` (the schema docs say not to include them).
      final draft = Recipe.fromJson({...obj, 'id': 'staging', 'image': ''});
      return RecipeImportResult(filename: filename, tier: 'json', draft: draft);
    } catch (_) {
      return RecipeImportResult(
        filename: filename,
        error: 'Off-schema JSON — see the expected shape.',
      );
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
    // Clear the saved row so the user can move on to the rest of the batch (or
    // upload something new once the list empties out).
    _removeEntry(entry);
    showToast(context, 'Saved to library');
  }

  Future<void> _saveAll() async {
    final ready = _entries.where((e) => e.ok).toList();
    if (ready.isEmpty) return;
    final saved = <_ReviewEntry>[];
    for (final entry in ready) {
      final draft = entry.draft;
      if (draft == null || draft.title.trim().isEmpty) continue;
      await widget.recipesRepo.save(draft.copyWith(id: newId('r')));
      saved.add(entry);
    }
    await widget.onChanged();
    if (!mounted) return;
    // Drop everything that saved, leaving only failures or title-less drafts.
    setState(() {
      _entries.removeWhere(saved.contains);
      if (_entries.isEmpty) _stage = _UploadStage.empty;
    });
    if (saved.isEmpty) {
      showToast(context, 'Give your recipes a title first');
    } else {
      showToast(context, 'Saved ${saved.length} to library');
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
                : 'Upload a JSON file, or write one from scratch',
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
        const _JsonHelper(),
        const SizedBox(height: 16),
        _stateBlock(
          title: 'Add recipes',
          desc: canAi ? 'no files selected' : 'JSON or manual',
          child: Column(children: [
            Dropzone(onFiles: _onFiles, jsonOnly: !canAi),
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
                      'Photo & PDF import is admin-enabled. You can still upload '
                      'JSON files or write a recipe by hand.',
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
              uploadsRepo: widget.uploadsRepo,
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
              label: ok > 1 ? 'Save all ($ok)' : 'Save all',
              variant: BtnVariant.primary,
              icon: Icons.done_all,
              onPressed: ok > 0 ? _saveAll : null,
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
    this.uploadsRepo,
  });

  final _ReviewEntry entry;
  final bool single;
  final ValueChanged<Recipe> onChange;
  final VoidCallback onSave;
  final VoidCallback onRemove;
  final UploadsRepository? uploadsRepo;

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
                uploadsRepo: widget.uploadsRepo,
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
    required this.onChange,
    required this.onSave,
    required this.onRemove,
    this.uploadsRepo,
  });
  final Recipe draft;
  final ValueChanged<Recipe> onChange;
  final VoidCallback onSave;
  final VoidCallback onRemove;
  final UploadsRepository? uploadsRepo;

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
    final uploadsRepo = this.uploadsRepo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (uploadsRepo != null) ...[
        label('Photo'),
        PhotoField(
          url: draft.image,
          uploadsRepo: uploadsRepo,
          onChanged: (url) => onChange(draft.copyWith(image: url)),
        ),
      ],
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
          label: 'Save to library',
          variant: BtnVariant.primary,
          icon: Icons.check,
          onPressed: onSave,
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
        color: rt.accentSoft,
        border: Border.all(color: rt.accent),
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
                Icon(Icons.data_object, size: 16, color: rt.accentInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Uploading JSON?',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: rt.accentInk)),
                ),
                Text('expected shape',
                    style: RecipeTypography.mono(
                        size: 11, color: rt.accentInk, letterSpacing: 0.5)),
                const SizedBox(width: 8),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: rt.accentInk),
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
                      color: rt.paper,
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
