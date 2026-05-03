import 'package:flutter/material.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';

typedef CellTap = void Function(int dayIdx, int mealIdx);
typedef DayToggle = void Function(int dayIdx);

class MealCalendar extends StatelessWidget {
  const MealCalendar({
    super.key,
    required this.plan,
    required this.recipesById,
    required this.collapsedDays,
    required this.onCellTap,
    required this.onDayToggle,
    required this.onRecipeTap,
    this.readOnly = false,
  });

  final MealPlan plan;
  final Map<String, Recipe> recipesById;
  final Set<int> collapsedDays;
  final CellTap onCellTap;
  final DayToggle onDayToggle;
  final ValueChanged<Recipe> onRecipeTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final cols = plan.meals.length;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header row
        Row(children: [
          _HeaderCell(text: '', width: 80, isCorner: true),
          for (final m in plan.meals) Expanded(child: _HeaderCell(text: m)),
        ]),
        // Day rows
        for (var di = 0; di < plan.days.length; di++)
          collapsedDays.contains(di)
              ? _CollapsedRow(
                  plan: plan,
                  dayIdx: di,
                  cols: cols,
                  recipesById: recipesById,
                  onTap: () => onDayToggle(di),
                )
              : _ExpandedRow(
                  plan: plan,
                  dayIdx: di,
                  cols: cols,
                  recipesById: recipesById,
                  onCellTap: (di, mi) {
                    final rid = plan.grid[di][mi];
                    if (readOnly) {
                      final r = rid == null ? null : recipesById[rid];
                      if (r != null) onRecipeTap(r);
                    } else {
                      onCellTap(di, mi);
                    }
                  },
                  onDayToggle: () => onDayToggle(di),
                ),
      ]),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.text, this.width, this.isCorner = false});
  final String text;
  final double? width;
  final bool isCorner;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final box = Container(
      decoration: BoxDecoration(
        color: rt.paper2,
        border: Border(
          bottom: BorderSide(color: rt.hair),
          right: BorderSide(color: rt.hair),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Text(text.toUpperCase(),
          style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.88)),
    );
    return width != null ? SizedBox(width: width, child: box) : box;
  }
}

class _ExpandedRow extends StatelessWidget {
  const _ExpandedRow({
    required this.plan,
    required this.dayIdx,
    required this.cols,
    required this.recipesById,
    required this.onCellTap,
    required this.onDayToggle,
  });
  final MealPlan plan;
  final int dayIdx;
  final int cols;
  final Map<String, Recipe> recipesById;
  final CellTap onCellTap;
  final VoidCallback onDayToggle;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 80,
          child: InkWell(
            onTap: onDayToggle,
            child: Container(
              decoration: BoxDecoration(
                color: rt.paper2,
                border: Border(bottom: BorderSide(color: rt.hair), right: BorderSide(color: rt.hair)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(plan.days[dayIdx],
                      style: RecipeTypography.mono(size: 11, weight: FontWeight.w500, color: rt.ink, letterSpacing: 0.44)),
                  Text(plan.dates[dayIdx],
                      style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.44)),
                ]),
                Positioned(top: 0, right: 0, child: Icon(Icons.expand_less, size: 16, color: rt.ink3)),
              ]),
            ),
          ),
        ),
        for (var mi = 0; mi < cols; mi++)
          Expanded(child: _Cell(
            plan: plan, dayIdx: dayIdx, mealIdx: mi,
            recipesById: recipesById,
            onTap: () => onCellTap(dayIdx, mi),
          )),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.plan,
    required this.dayIdx,
    required this.mealIdx,
    required this.recipesById,
    required this.onTap,
  });
  final MealPlan plan;
  final int dayIdx;
  final int mealIdx;
  final Map<String, Recipe> recipesById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final rid = plan.grid[dayIdx][mealIdx];
    final recipe = rid == null ? null : recipesById[rid];

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        decoration: BoxDecoration(
          color: recipe == null ? null : rt.paper,
          border: Border(
            bottom: BorderSide(color: rt.hair),
            right: BorderSide(color: rt.hair),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: ClipRect(
          child: recipe == null
              ? CustomPaint(
                  painter: _StripePainter(rt.paper, rt.paper2),
                  child: const SizedBox.expand(),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: rt.paper2,
                      border: Border.all(color: rt.hair),
                      borderRadius: BorderRadius.circular(4),
                      image: recipe.image.isEmpty
                          ? null
                          : DecorationImage(image: NetworkImage(recipe.image), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(recipe.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: rt.ink, height: 1.25)),
                  ),
                ]),
        ),
      ),
    );
  }
}

class _CollapsedRow extends StatelessWidget {
  const _CollapsedRow({
    required this.plan,
    required this.dayIdx,
    required this.cols,
    required this.recipesById,
    required this.onTap,
  });
  final MealPlan plan;
  final int dayIdx;
  final int cols;
  final Map<String, Recipe> recipesById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final assigned = plan.grid[dayIdx].whereType<String>().length;
    final names = plan.grid[dayIdx].asMap().entries.where((e) => e.value != null).map((e) {
      final r = recipesById[e.value!];
      return r?.title ?? '?';
    }).join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: rt.paper2,
          border: Border(bottom: BorderSide(color: rt.hair)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          SizedBox(
            width: 56,
            child: Text(plan.days[dayIdx],
                style: RecipeTypography.mono(size: 11, weight: FontWeight.w500, color: rt.ink, letterSpacing: 0.44)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              names.isEmpty ? '— nothing assigned —' : names,
              style: TextStyle(fontSize: 13, color: rt.ink2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$assigned / $cols',
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.44)),
          Icon(Icons.expand_more, size: 16, color: rt.ink3),
        ]),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.bg, this.stripe);
  final Color bg;
  final Color stripe;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = bg;
    canvas.drawRect(Offset.zero & size, paint);
    final s = Paint()
      ..color = stripe
      ..strokeWidth = 1;
    final spacing = 7.0;
    for (var x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), s);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.bg != bg || old.stripe != stripe;
}
