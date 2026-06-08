import 'package:flutter/material.dart';

import '../../models/collection.dart';
import '../../theme/app_theme.dart';
import '../buttons.dart';
import '../modal_shell.dart';

Future<bool> openDeleteCollectionModal(BuildContext context, Collection c) async {
  final result = await showRecipeModal<bool>(
    context: context,
    builder: (ctx) => ModalShell(
      title: 'Delete collection?',
      subtitle: '"${c.name}" will be removed.',
      actions: [
        const CancelButton(),
        Btn(
          label: 'Delete',
          variant: BtnVariant.dangerSolid,
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
        ),
      ],
      child: Text(
        'The collection is removed but its recipes stay in your library. This is not undoable.',
        style: TextStyle(color: ctx.rt.ink2, fontSize: 14),
      ),
    ),
  );
  return result == true;
}
