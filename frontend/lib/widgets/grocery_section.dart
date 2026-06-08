import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/grocery_item.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../utils/grocery_aggregator.dart';
import 'toast.dart';

/// The grocery section under a plan: collapsible meal-picker grid + the
/// aggregated, categorized ingredient list with checkboxes.
class GrocerySection extends StatefulWidget {
  const GrocerySection({
    super.key,
    required this.plan,
    required this.recipesById,
    required this.selection,
    required this.onSelectionChange,
  });

  final MealPlan plan;
  final Map<String, Recipe> recipesById;
  // Set of "$dayIdx-$mealIdx" strings.
  final Set<String> selection;
  final ValueChanged<Set<String>> onSelectionChange;

  @override
  State<GrocerySection> createState() => _GrocerySectionState();
}

class _GrocerySectionState extends State<GrocerySection> {
  bool _pickerCollapsed = true;
  final Set<String> _checked = {};

  List<({int di, int mi, String rid})> get _filledCells {
    final out = <({int di, int mi, String rid})>[];
    for (var di = 0; di < widget.plan.grid.length; di++) {
      final row = widget.plan.grid[di];
      for (var mi = 0; mi < row.length; mi++) {
        final r = row[mi];
        if (r != null) out.add((di: di, mi: mi, rid: r));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final filled = _filledCells;
    final selected = filled.where((c) => widget.selection.contains('${c.di}-${c.mi}')).map((c) => c.rid).toList();
    final recipes = selected.map((rid) => widget.recipesById[rid]).whereType<Recipe>().toList();
    final cats = aggregateIngredients(recipes);
    final totalItems = cats.values.fold<int>(0, (a, b) => a + b.length);

    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.cardBR,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Grocery list',
              style: RecipeTypography.serif(size: 24, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.24)),
          const SizedBox(width: 12),
          Text('$totalItems items · ${selected.length}/${filled.length} meals',
              style: RecipeTypography.mono(size: 11.5, color: rt.ink3, letterSpacing: 0.46)),
          const Spacer(),
          if (totalItems > 0)
            TextButton.icon(
              onPressed: () => _copyList(cats),
              icon: Icon(Icons.copy_outlined, size: 16, color: rt.ink2),
              label: Text('Copy list', style: TextStyle(color: rt.ink2, fontSize: 13)),
            ),
          if (filled.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _pickerCollapsed = !_pickerCollapsed),
              icon: Icon(_pickerCollapsed ? Icons.expand_more : Icons.expand_less, size: 16, color: rt.ink2),
              label: Text(
                _pickerCollapsed ? 'Show meal picker' : 'Hide meal picker',
                style: TextStyle(color: rt.ink2, fontSize: 13),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (filled.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Assign recipes to the calendar to populate your grocery list.',
              style: TextStyle(color: rt.ink3, fontSize: 14),
            ),
          )
        else ...[
          if (!_pickerCollapsed) _picker(filled),
          const SizedBox(height: 18),
          _buildList(cats),
        ],
      ]),
    );
  }

  Widget _picker(List<({int di, int mi, String rid})> filled) {
    final rt = context.rt;
    final p = widget.plan;
    final allOn = filled.every((c) => widget.selection.contains('${c.di}-${c.mi}'));
    return Container(
      decoration: BoxDecoration(
        color: rt.paper2,
        border: Border.all(color: rt.hair),
        borderRadius: RecipeRadius.fieldBR,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Include in grocery list',
              style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.66)),
          const Spacer(),
          TextButton(
            onPressed: () {
              final next = Set<String>.from(widget.selection);
              if (allOn) {
                next.clear();
              } else {
                next.addAll(filled.map((c) => '${c.di}-${c.mi}'));
              }
              widget.onSelectionChange(next);
            },
            child: Text(
              allOn ? 'Deselect all' : 'Select all',
              style: TextStyle(color: rt.accentInk, fontSize: 12),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Toggle individual meals across the week',
              style: TextStyle(color: rt.ink3, fontSize: 12.5)),
        ),
        Table(
          columnWidths: {
            0: const FixedColumnWidth(84),
            for (var i = 0; i < p.days.length; i++) (i + 1): const FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (var di = 0; di < p.days.length; di++)
                  _DayHeader(day: p.days[di], date: p.dates[di]),
              ],
            ),
            for (var mi = 0; mi < p.meals.length; mi++)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                  child: Text(
                    p.meals[mi].toUpperCase(),
                    style: RecipeTypography.mono(size: 10.5, color: rt.ink2, letterSpacing: 0.63),
                  ),
                ),
                for (var di = 0; di < p.days.length; di++)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: _PickerCell(
                      recipe: widget.recipesById[p.grid[di][mi]],
                      rid: p.grid[di][mi],
                      checked: widget.selection.contains('$di-$mi'),
                      onTap: () {
                        if (p.grid[di][mi] == null) return;
                        final key = '$di-$mi';
                        final next = Set<String>.from(widget.selection);
                        if (next.contains(key)) {
                          next.remove(key);
                        } else {
                          next.add(key);
                        }
                        widget.onSelectionChange(next);
                      },
                    ),
                  ),
              ]),
          ],
        ),
      ]),
    );
  }

  Widget _buildList(Map<GroceryCategory, List<GroceryItem>> cats) {
    final rt = context.rt;
    final hasAny = cats.values.any((l) => l.isNotEmpty);
    if (!hasAny) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text('No ingredients (no meals selected).',
            style: TextStyle(color: rt.ink3, fontSize: 14)),
      );
    }
    final activeCats = GroceryCategory.values.where((c) => cats[c]!.isNotEmpty).toList();
    return Wrap(
      spacing: 32,
      runSpacing: 24,
      children: [
        for (final cat in activeCats)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: rt.hair)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(cat.label.toUpperCase(),
                          style: RecipeTypography.mono(size: 11, color: rt.accentInk, letterSpacing: 0.88)),
                    ),
                    Text('${cats[cat]!.length}',
                        style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0)),
                  ]),
                ),
                for (final it in cats[cat]!) _ItemRow(
                  item: it,
                  checked: _checked.contains(_keyFor(it)),
                  onChange: (v) => setState(() {
                    final k = _keyFor(it);
                    if (v) {
                      _checked.add(k);
                    } else {
                      _checked.remove(k);
                    }
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _keyFor(GroceryItem it) => '${it.name}|${it.unit}';

  Future<void> _copyList(Map<GroceryCategory, List<GroceryItem>> cats) async {
    final text = formatGroceryList(cats);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast(context, 'Grocery list copied to clipboard');
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.date});
  final String day;
  final String date;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: rt.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(day.toUpperCase(),
              style: RecipeTypography.mono(size: 10.5, weight: FontWeight.w600, color: rt.ink2, letterSpacing: 0.63)),
          Text(date,
              style: RecipeTypography.mono(size: 9.5, color: rt.ink3, letterSpacing: 0.38)),
        ],
      ),
    );
  }
}

class _PickerCell extends StatelessWidget {
  const _PickerCell({
    required this.recipe,
    required this.rid,
    required this.checked,
    required this.onTap,
  });
  final Recipe? recipe;
  final String? rid;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    // Empty cell: dashed transparent box, no checkbox.
    if (rid == null) {
      return DottedBox(color: rt.hair, height: 34);
    }
    final title = recipe?.title ?? '?';
    final onBg = Color.alphaBlend(rt.accent.withValues(alpha: 0.10), rt.paper);
    final onBorder = Color.alphaBlend(rt.accent.withValues(alpha: 0.40), rt.hair);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? onBg : rt.paper,
          border: Border.all(color: checked ? onBorder : rt.hair),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 13, height: 13,
              decoration: BoxDecoration(
                color: checked ? rt.accent : rt.paper,
                border: Border.all(color: checked ? rt.accent : rt.ink3, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: checked
                  ? Center(
                      child: Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(color: rt.paper, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Tooltip(
                message: title,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: checked ? rt.ink : rt.ink3,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed-border placeholder used for empty calendar cells in the grocery
/// picker — matches `.g-cell.g-empty` from the wireframe.
class DottedBox extends StatelessWidget {
  const DottedBox({super.key, required this.color, required this.height});
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _DashedRectPainter(color)),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(6),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        dashed.addPath(metric.extractPath(d, (d + dash).clamp(0, metric.length)), Offset.zero);
        d += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.checked, required this.onChange});
  final GroceryItem item;
  final bool checked;
  final ValueChanged<bool> onChange;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final amt = formatAmt(item.amount);
    final qty = [amt, item.unit].where((s) => s.isNotEmpty).join(' ');
    return InkWell(
      onTap: () => onChange(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 18, height: 18,
            child: Checkbox(
              value: checked,
              onChanged: (v) => onChange(v ?? false),
              activeColor: rt.accent,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          if (qty.isNotEmpty) ...[
            SizedBox(
              width: 90,
              child: Text(qty,
                  style: RecipeTypography.mono(size: 13, color: rt.ink2, letterSpacing: 0)),
            ),
          ],
          Expanded(
            child: Text(
              item.name,
              style: TextStyle(
                fontSize: 14,
                color: rt.ink,
                decoration: checked ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: rt.ink3,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
