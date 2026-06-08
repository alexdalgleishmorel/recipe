import 'package:flutter/material.dart';

import '../../models/meal_plan.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_format.dart';
import '../../utils/id_gen.dart';
import '../buttons.dart';
import '../modal_shell.dart';
import '../toast.dart';

Future<MealPlan?> openNewPlanModal(BuildContext context) async {
  return showRecipeModal<MealPlan>(
    context: context,
    builder: (ctx) => const _NewPlanForm(),
  );
}

class _NewPlanForm extends StatefulWidget {
  const _NewPlanForm();
  @override
  State<_NewPlanForm> createState() => _NewPlanFormState();
}

class _NewPlanFormState extends State<_NewPlanForm> {
  final _name = TextEditingController();
  late DateTime _start;
  late DateTime _end;
  final Set<String> _meals = {'Breakfast', 'Dinner'};

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _end = _start.add(const Duration(days: 6));
  }

  Future<void> _pick({required bool start}) async {
    final initial = start ? _start : _end;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (result == null) return;
    setState(() {
      if (start) {
        _start = result;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(days: 6));
      } else {
        _end = result;
        if (_end.isBefore(_start)) _start = _end.subtract(const Duration(days: 6));
      }
    });
  }

  void _submit() {
    if (_meals.isEmpty) {
      showToast(context, 'A plan needs at least one meal');
      return;
    }
    final r = expandRange(_start, _end);
    final mealsOrdered = ['Breakfast', 'Lunch', 'Dinner'].where(_meals.contains).toList();
    final plan = MealPlan(
      id: newId('p'),
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      status: PlanStatus.draft,
      start: r.start,
      end: r.end,
      days: r.days,
      dates: r.dates,
      meals: mealsOrdered,
      candidates: const [],
      grid: List.generate(r.days.length, (_) => List<String?>.filled(mealsOrdered.length, null)),
    );
    Navigator.of(context, rootNavigator: true).pop(plan);
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: rt.ink3),
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          enabledBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.hair2)),
          focusedBorder: OutlineInputBorder(borderRadius: RecipeRadius.fieldBR, borderSide: BorderSide(color: rt.ink3)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 14),
          child: Text(t.toUpperCase(),
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.66)),
        );
    return ModalShell(
      title: 'New meal plan',
      subtitle: 'Sketch a week, gather candidates, finalize when ready.',
      actions: [
        const CancelButton(),
        Btn(label: 'Create draft', variant: BtnVariant.primary, onPressed: _submit),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        label('Plan name (optional)'),
        TextField(controller: _name, decoration: dec("e.g. Thanksgiving Prep Week")),
        label('Date range'),
        Row(children: [
          Expanded(child: _DateBox(label: formatMonthDay(_start), onTap: () => _pick(start: true))),
          const SizedBox(width: 10),
          Expanded(child: _DateBox(label: formatMonthDay(_end), onTap: () => _pick(start: false))),
        ]),
        label('Meals to include'),
        Column(children: [
          for (final m in const ['Breakfast', 'Lunch', 'Dinner'])
            _MealCheckbox(
              label: m,
              checked: _meals.contains(m),
              onChange: (v) => setState(() {
                if (v) {
                  _meals.add(m);
                } else {
                  _meals.remove(m);
                }
              }),
            ),
        ]),
      ]),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: RecipeRadius.fieldBR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(color: rt.hair2),
          borderRadius: RecipeRadius.fieldBR,
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 14, color: rt.ink3),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: rt.ink, fontSize: 14)),
        ]),
      ),
    );
  }
}

class _MealCheckbox extends StatelessWidget {
  const _MealCheckbox({required this.label, required this.checked, required this.onChange});
  final String label;
  final bool checked;
  final ValueChanged<bool> onChange;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onChange(!checked),
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: rt.paper,
            border: Border.all(color: rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(children: [
            SizedBox(
              width: 16, height: 16,
              child: Checkbox(
                value: checked,
                activeColor: rt.accent,
                onChanged: (v) => onChange(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14, color: rt.ink)),
          ]),
        ),
      ),
    );
  }
}
