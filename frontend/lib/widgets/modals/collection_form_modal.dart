import 'package:flutter/material.dart';

import '../../models/collection.dart';
import '../../theme/app_theme.dart';
import '../../utils/id_gen.dart';
import '../buttons.dart';
import '../modal_shell.dart';
import '../toast.dart';

/// Create-or-rename form for a [Collection]. Pass [existing] to edit name +
/// description in place; omit it to create a brand new collection (preserving
/// no recipe IDs). Returns the saved [Collection] (with a generated id when
/// creating) or null on cancel.
Future<Collection?> openCollectionFormModal(
  BuildContext context, {
  Collection? existing,
}) async {
  return showRecipeModal<Collection>(
    context: context,
    builder: (ctx) => _CollectionForm(existing: existing),
  );
}

class _CollectionForm extends StatefulWidget {
  const _CollectionForm({this.existing});
  final Collection? existing;
  @override
  State<_CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<_CollectionForm> {
  late final TextEditingController _name;
  late final TextEditingController _desc;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'A collection needs a name');
      return;
    }
    final desc = _desc.text.trim();
    final result = widget.existing == null
        ? Collection(id: newId('c'), name: name, description: desc, recipeIds: const [])
        : widget.existing!.copyWith(name: name, description: desc);
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final editing = widget.existing != null;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: rt.ink3),
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.accent)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 14),
          child: Text(t.toUpperCase(),
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.66)),
        );
    return ModalShell(
      title: editing ? 'Rename collection' : 'New collection',
      subtitle: editing
          ? 'Update the name or description.'
          : 'Group recipes into a named set you can revisit.',
      actions: [
        const CancelButton(),
        Btn(label: editing ? 'Save' : 'Create', variant: BtnVariant.primary, onPressed: _submit),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        label('Name'),
        TextField(controller: _name, autofocus: true, decoration: dec('e.g. Weeknight Dinners')),
        label('Description (optional)'),
        TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: dec('A short note about this collection')),
      ]),
    );
  }
}
