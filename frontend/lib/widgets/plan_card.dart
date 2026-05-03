import 'package:flutter/material.dart';

import '../models/meal_plan.dart';
import '../theme/app_theme.dart';

class PlanCard extends StatefulWidget {
  const PlanCard({super.key, required this.plan, required this.onTap});
  final MealPlan plan;
  final VoidCallback onTap;
  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  bool _hover = false;

  int get _assignedCells {
    var n = 0;
    for (final row in widget.plan.grid) {
      for (final c in row) {
        if (c != null) n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final p = widget.plan;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: rt.paper,
            border: Border.all(color: _hover ? rt.ink3 : rt.hair),
            borderRadius: RecipeRadius.cardBR,
          ),
          child: LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth > 600;
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName,
                    style: RecipeTypography.serif(size: 20, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.2)),
                const SizedBox(height: 4),
                Text('${p.start.toUpperCase()}–${p.end.toUpperCase()}',
                    style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0.48)),
              ],
            );
            final mid = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Meals'),
                const SizedBox(height: 3),
                Text(p.meals.join(', '), style: TextStyle(fontSize: 13.5, color: rt.ink2)),
              ],
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Recipes'),
                const SizedBox(height: 3),
                Text('$_assignedCells assigned · ${p.candidates.length} candidates',
                    style: TextStyle(fontSize: 13.5, color: rt.ink2)),
              ],
            );
            final badge = _Badge(status: p.status);

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: left), badge]),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: mid), const SizedBox(width: 12), Expanded(child: right)]),
                ],
              );
            }
            return Row(children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: mid),
              const SizedBox(width: 24),
              Expanded(flex: 3, child: right),
              const SizedBox(width: 16),
              badge,
            ]);
          }),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t.toUpperCase(),
      style: RecipeTypography.mono(size: 10.5, color: context.rt.ink3, letterSpacing: 0.84));
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});
  final PlanStatus status;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final isFinal = status == PlanStatus.finalized;
    final color = isFinal ? rt.accentInk : rt.ink2;
    final bg = isFinal ? rt.accentSoft : rt.paper2;
    final border = isFinal
        ? Color.alphaBlend(rt.accent.withValues(alpha: 0.25), rt.paper)
        : rt.hair2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(isFinal ? 'FINALIZED' : 'DRAFT',
            style: RecipeTypography.mono(size: 11, color: color, letterSpacing: 0.66)),
      ]),
    );
  }
}
