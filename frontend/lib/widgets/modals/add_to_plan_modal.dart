import 'package:flutter/material.dart';

import '../../models/meal_plan.dart';
import '../../models/recipe.dart';
import '../../theme/app_theme.dart';
import '../../utils/id_gen.dart';
import '../modal_shell.dart';

class AddToPlanResult {
  AddToPlanResult({required this.plan, required this.created});
  final MealPlan plan;
  final bool created;
}

Future<AddToPlanResult?> openAddToPlanModal(
  BuildContext context, {
  required Recipe recipe,
  required List<MealPlan> plans,
}) async {
  final drafts = plans.where((p) => p.status == PlanStatus.draft).toList();
  return showRecipeModal<AddToPlanResult>(
    context: context,
    builder: (ctx) {
      final rt = ctx.rt;
      return ModalShell(
        title: 'Add to a meal plan',
        subtitle: 'Flag "${recipe.title}" as a candidate for one of your drafts.',
        actions: [const CancelButton()],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in drafts)
              _PlanRow(
                title: p.displayName,
                subtitle: '${p.start}–${p.end} · ${p.candidates.length} candidates',
                onTap: () {
                  if (p.candidates.contains(recipe.id)) {
                    Navigator.of(ctx, rootNavigator: true).pop(AddToPlanResult(plan: p, created: false));
                    return;
                  }
                  final updated = p.copyWith(candidates: [...p.candidates, recipe.id]);
                  Navigator.of(ctx, rootNavigator: true).pop(AddToPlanResult(plan: updated, created: false));
                },
              ),
            if (drafts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No draft plans yet. Create one below.',
                  style: TextStyle(color: rt.ink3, fontSize: 13.5),
                ),
              ),
            const SizedBox(height: 12),
            Text('OR', style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
            const SizedBox(height: 6),
            _PlanRow(
              title: 'Start a new draft plan',
              subtitle: 'Defaults to next 7 days · breakfast + dinner',
              accent: true,
              onTap: () {
                final today = DateTime.now();
                final inSeven = today.add(const Duration(days: 6));
                String fmt(DateTime d) {
                  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                  return '${m[d.month-1]} ${d.day}';
                }
                final days = <String>[]; final dates = <String>[];
                for (var i = 0; i < 7; i++) {
                  final d = today.add(Duration(days: i));
                  const dn = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                  days.add(dn[d.weekday - 1]);
                  dates.add('${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}');
                }
                final plan = MealPlan(
                  id: newId('p'),
                  name: null,
                  status: PlanStatus.draft,
                  start: fmt(today),
                  end: fmt(inSeven),
                  days: days,
                  dates: dates,
                  meals: const ['Breakfast', 'Dinner'],
                  candidates: [recipe.id],
                  grid: List.generate(7, (_) => List<String?>.filled(2, null)),
                  chat: const [],
                );
                Navigator.of(ctx, rootNavigator: true).pop(AddToPlanResult(plan: plan, created: true));
              },
            ),
          ],
        ),
      );
    },
  );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.title, required this.subtitle, required this.onTap, this.accent = false});
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent ? Color.alphaBlend(rt.accent.withValues(alpha: 0.06), rt.paper) : rt.paper,
            border: Border.all(color: accent ? rt.accent : rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontWeight: FontWeight.w500, color: accent ? rt.accentInk : rt.ink, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: rt.ink3)),
                  ],
                ),
              ),
              if (accent) Icon(Icons.add, size: 16, color: rt.accentInk),
            ],
          ),
        ),
      ),
    );
  }
}
