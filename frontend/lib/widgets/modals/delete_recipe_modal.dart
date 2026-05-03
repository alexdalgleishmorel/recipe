import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_theme.dart';
import '../buttons.dart';
import '../modal_shell.dart';

Future<bool> openDeleteRecipeModal(BuildContext context, Recipe r) async {
  final result = await showRecipeModal<bool>(
    context: context,
    builder: (ctx) => ModalShell(
      title: 'Delete recipe?',
      subtitle: '"${r.title}" will be removed from your library.',
      actions: [
        const CancelButton(),
        Btn(
          label: 'Delete',
          variant: BtnVariant.dangerSolid,
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
        ),
      ],
      child: Text(
        'This is permanent — recipe and its ingredients/steps will be lost.',
        style: TextStyle(color: ctx.rt.ink2, fontSize: 14),
      ),
    ),
  );
  return result == true;
}
