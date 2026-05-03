import 'package:flutter/material.dart';

import '../../models/meal_plan.dart';
import '../../theme/app_theme.dart';
import '../buttons.dart';
import '../modal_shell.dart';

Future<bool> openFinalizePlanModal(BuildContext context, MealPlan p) async {
  final r = await showRecipeModal<bool>(
    context: context,
    builder: (ctx) => ModalShell(
      title: 'Finalize this plan?',
      subtitle: 'Locks the calendar; you can still review the grocery list.',
      actions: [
        const CancelButton(),
        Btn(
          label: 'Finalize',
          variant: BtnVariant.accent,
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
        ),
      ],
      child: Text(
        '“${p.displayName}” will move out of drafts and into your finalized plans.',
        style: TextStyle(color: ctx.rt.ink2, fontSize: 14),
      ),
    ),
  );
  return r == true;
}

Future<bool> openDeletePlanModal(BuildContext context, MealPlan p) async {
  final r = await showRecipeModal<bool>(
    context: context,
    builder: (ctx) => ModalShell(
      title: 'Delete this plan?',
      subtitle: '“${p.displayName}” will be removed.',
      actions: [
        const CancelButton(),
        Btn(
          label: 'Delete',
          variant: BtnVariant.dangerSolid,
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
        ),
      ],
      child: Text(
        'Candidates and assigned cells will be lost. This is not undoable.',
        style: TextStyle(color: ctx.rt.ink2, fontSize: 14),
      ),
    ),
  );
  return r == true;
}
