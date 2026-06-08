import 'package:flutter/material.dart';

import '../../models/meal_plan.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_format.dart';
import '../buttons.dart';
import '../date_range_field.dart';
import '../modal_shell.dart';

/// Edit a draft plan's date range. Returns the chosen start/end `DateTime`s, or
/// null if cancelled. The caller re-expands the range and resizes the plan's
/// grid, preserving any assignment whose date stays in range.
Future<({DateTime start, DateTime end})?> openEditPlanDatesModal(
  BuildContext context, {
  required MealPlan plan,
}) async {
  return showRecipeModal<({DateTime start, DateTime end})>(
    context: context,
    builder: (ctx) => _EditPlanDatesForm(plan: plan),
  );
}

class _EditPlanDatesForm extends StatefulWidget {
  const _EditPlanDatesForm({required this.plan});
  final MealPlan plan;
  @override
  State<_EditPlanDatesForm> createState() => _EditPlanDatesFormState();
}

class _EditPlanDatesFormState extends State<_EditPlanDatesForm> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    // Reconstruct DateTimes from the plan's stored "MM/DD" strings to seed the
    // picker (best-effort — the user re-picks the actual range).
    final dates = widget.plan.dates;
    _start = dates.isNotEmpty ? parseSlashDateNear(dates.first) : DateTime.now();
    _end = dates.isNotEmpty
        ? parseSlashDateNear(dates.last)
        : _start.add(const Duration(days: 6));
    if (_end.isBefore(_start)) _end = _start;
  }

  void _submit() {
    Navigator.of(context, rootNavigator: true).pop((start: _start, end: _end));
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return ModalShell(
      title: 'Edit dates',
      subtitle: 'Change the plan\'s date range. Meals placed on a date that '
          'stays in range are kept; dropped dates are cleared.',
      actions: [
        const CancelButton(),
        Btn(label: 'Save dates', variant: BtnVariant.primary, onPressed: _submit),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('DATE RANGE',
              style: RecipeTypography.mono(
                  size: 11, color: rt.ink3, letterSpacing: 0.66)),
        ),
        DateRangeField(
          start: _start,
          end: _end,
          onChanged: (s, e) => setState(() {
            _start = s;
            _end = e;
          }),
        ),
      ]),
    );
  }
}
