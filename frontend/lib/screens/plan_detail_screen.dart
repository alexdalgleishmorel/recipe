import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/grocery_aggregator.dart';
import '../utils/id_gen.dart';
import '../widgets/buttons.dart';
import '../widgets/candidates_panel.dart';
import '../widgets/grocery_section.dart';
import '../widgets/meal_calendar.dart';
import '../widgets/modals/confirm_modals.dart';
import '../widgets/modals/edit_plan_dates_modal.dart';
import '../widgets/modals/recipe_picker_modal.dart';
import '../widgets/page_head.dart';
import '../widgets/toast.dart';
import 'recipe_detail_screen.dart';

class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen({
    super.key,
    required this.planId,
    required this.plansRepo,
    required this.recipesRepo,
    required this.onChanged,
    this.uploadsRepo,
  });

  final String planId;
  final MealPlansRepository plansRepo;
  final RecipesRepository recipesRepo;
  final Future<void> Function() onChanged;
  final UploadsRepository? uploadsRepo;

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  MealPlan? _plan;
  List<Recipe> _allRecipes = const [];
  Map<String, Recipe> _byId = const {};
  bool _loading = true;

  final Set<int> _collapsedDays = {};
  Set<String> _grocerySel = {};
  bool _editingTitle = false;
  late final TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.plansRepo.get(widget.planId),
      widget.recipesRepo.list(),
    ]);
    final plan = results[0] as MealPlan?;
    final recipes = results[1] as List<Recipe>;
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _allRecipes = recipes;
      _byId = {for (final r in recipes) r.id: r};
      _loading = false;
      // Default grocery selection: every filled cell.
      if (plan != null) {
        _grocerySel = {
          for (var di = 0; di < plan.grid.length; di++)
            for (var mi = 0; mi < plan.grid[di].length; mi++)
              if (plan.grid[di][mi] != null) '$di-$mi',
        };
      }
      _titleCtrl.text = plan?.name ?? '';
    });
  }

  Future<void> _save(MealPlan p) async {
    setState(() => _plan = p);
    await widget.plansRepo.save(p);
    await widget.onChanged();
  }

  Future<void> _toggleMeal(String meal) async {
    final p = _plan!;
    if (p.meals.contains(meal)) {
      if (p.meals.length == 1) {
        showToast(context, 'A plan needs at least one meal');
        return;
      }
      final mealIdx = p.meals.indexOf(meal);
      final newGrid = p.grid.map((row) {
        final next = List<String?>.from(row);
        next.removeAt(mealIdx);
        return next;
      }).toList();
      final newMeals = List<String>.from(p.meals)..remove(meal);
      await _save(p.copyWith(meals: newMeals, grid: newGrid));
    } else {
      const order = ['Breakfast', 'Lunch', 'Dinner'];
      final newMeals = List<String>.from(p.meals)..add(meal);
      newMeals.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
      final insertAt = newMeals.indexOf(meal);
      final newGrid = p.grid.map((row) {
        final next = List<String?>.from(row);
        next.insert(insertAt, null);
        return next;
      }).toList();
      await _save(p.copyWith(meals: newMeals, grid: newGrid));
    }
  }

  Future<void> _pickCell(int dayIdx, int mealIdx) async {
    final p = _plan!;
    final current = p.grid[dayIdx][mealIdx];
    final result = await openRecipePicker(
      context,
      title: 'Assign a recipe',
      subtitle: '${p.days[dayIdx]} · ${p.meals[mealIdx]}',
      recipes: _allRecipes,
      candidateIds: p.candidates,
      currentRecipeId: current,
    );
    if (result == null) return;
    final newGrid = p.grid.map((r) => List<String?>.from(r)).toList();
    newGrid[dayIdx][mealIdx] = result.id;
    await _save(p.copyWith(grid: newGrid));
    if (!mounted) return;
    showToast(context, 'Assigned ${result.title}');
  }

  Future<void> _addCandidate() async {
    final p = _plan!;
    final result = await openRecipePicker(
      context,
      title: 'Add a candidate',
      recipes: _allRecipes.where((r) => !p.candidates.contains(r.id)).toList(),
    );
    if (result == null) return;
    await _save(p.copyWith(candidates: [...p.candidates, result.id]));
  }

  Future<void> _editDates() async {
    final p = _plan!;
    final picked = await openEditPlanDatesModal(context, plan: p);
    if (picked == null) return;
    final r = expandRange(picked.start, picked.end);
    // Resize the grid to the new day count, preserving each assignment whose
    // date stays in range. Rows for dropped dates are discarded; dates added to
    // the range start empty. Meals (the grid's columns) are untouched.
    final byDate = <String, List<String?>>{
      for (var i = 0; i < p.dates.length && i < p.grid.length; i++)
        p.dates[i]: p.grid[i],
    };
    final grid = [
      for (final date in r.dates)
        byDate[date] ?? List<String?>.filled(p.meals.length, null),
    ];
    setState(() {
      // Day indices shifted, so stale collapse/grocery state no longer maps —
      // reset grocery selection to every filled cell (the load-time default).
      _collapsedDays.clear();
      _grocerySel = {
        for (var di = 0; di < grid.length; di++)
          for (var mi = 0; mi < grid[di].length; mi++)
            if (grid[di][mi] != null) '$di-$mi',
      };
    });
    await _save(p.copyWith(
      start: r.start,
      end: r.end,
      days: r.days,
      dates: r.dates,
      grid: grid,
    ));
    if (!mounted) return;
    showToast(context, 'Dates updated');
  }

  Future<void> _finalize() async {
    final p = _plan!;
    final ok = await openFinalizePlanModal(context, p);
    if (!ok) return;
    await _save(p.copyWith(status: PlanStatus.finalized));
    // Finalizing produces a usable downstream: copy the aggregated grocery
    // list (from the currently selected meals) to the clipboard.
    final copied = await _copyGroceryList();
    if (!mounted) return;
    showToast(context, copied ? 'Finalized — grocery list copied' : 'Meal plan finalized');
  }

  /// Aggregate the selected meals' ingredients and copy the list to the
  /// clipboard. Returns whether anything was copied.
  Future<bool> _copyGroceryList() async {
    final p = _plan!;
    final ids = <String>[];
    for (var di = 0; di < p.grid.length; di++) {
      for (var mi = 0; mi < p.grid[di].length; mi++) {
        if (p.grid[di][mi] != null && _grocerySel.contains('$di-$mi')) {
          ids.add(p.grid[di][mi]!);
        }
      }
    }
    final recipes = ids.map((id) => _byId[id]).whereType<Recipe>().toList();
    final text = formatGroceryList(aggregateIngredients(recipes));
    if (text.isEmpty) return false;
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  Future<void> _delete() async {
    final p = _plan!;
    final ok = await openDeletePlanModal(context, p);
    if (!ok) return;
    await widget.plansRepo.delete(p.id);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Meal plan deleted');
    Navigator.of(context).pop();
  }

  Future<void> _duplicate() async {
    final p = _plan!;
    final copy = p.copyWith(
      id: newId('p'),
      status: PlanStatus.draft,
      name: '${p.displayName} (copy)',
      nameExplicit: true,
    );
    // Use the saved copy's id: the backend assigns its own id on create, so
    // navigating with the pre-save (client) id would 404 ("not found").
    final saved = await widget.plansRepo.save(copy);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Duplicated as draft');
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PlanDetailScreen(
        planId: saved.id,
        plansRepo: widget.plansRepo,
        recipesRepo: widget.recipesRepo,
        onChanged: widget.onChanged,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (_loading) {
      return Scaffold(backgroundColor: rt.paper, body: const Center(child: CircularProgressIndicator()));
    }
    final p = _plan;
    if (p == null) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(child: Text('Plan not found.', style: TextStyle(color: rt.ink3))),
      );
    }
    final readOnly = p.status == PlanStatus.finalized;
    return Scaffold(
      backgroundColor: rt.paper,
      body: ContentScroll(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _back(),
          const SizedBox(height: 12),
          _header(p, readOnly),
          const SizedBox(height: 28),
          if (!readOnly) _mealToggles(p),
          if (!readOnly) const SizedBox(height: 14),
          _layout(p, readOnly),
          const SizedBox(height: 32),
          GrocerySection(
            plan: p,
            recipesById: _byId,
            selection: _grocerySel,
            onSelectionChange: (s) => setState(() => _grocerySel = s),
          ),
        ]),
      ),
    );
  }

  Widget _back() {
    final rt = context.rt;
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_back, size: 14, color: rt.ink3),
          const SizedBox(width: 6),
          Text('BACK TO PLANS',
              style: RecipeTypography.mono(size: 13, color: rt.ink3, letterSpacing: 0.52)),
        ]),
      ),
    );
  }

  Widget _header(MealPlan p, bool readOnly) {
    final rt = context.rt;
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth > 760;
      final left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editingTitle)
            SizedBox(
              width: 480,
              child: TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: RecipeTypography.serif(size: 38, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.76),
                onSubmitted: (_) => _commitTitle(),
                onEditingComplete: _commitTitle,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: rt.accent)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: rt.accent)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: rt.accent)),
                ),
              ),
            )
          else
            InkWell(
              onTap: readOnly ? null : () => setState(() {
                    _editingTitle = true;
                    _titleCtrl.text = p.name ?? '';
                  }),
              child: Text(
                p.displayName,
                style: RecipeTypography.serif(
                  size: 38, weight: FontWeight.w500,
                  color: rt.ink, letterSpacing: -0.76,
                ).copyWith(fontStyle: p.isDefaultName ? FontStyle.italic : FontStyle.normal),
              ),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${p.start.toUpperCase()}–${p.end.toUpperCase()}',
                style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0.48)),
            const SizedBox(width: 8),
            _StatusBadge(status: p.status),
          ]),
        ],
      );
      final right = Wrap(
        spacing: 8, runSpacing: 8,
        alignment: WrapAlignment.end,
        children: readOnly
            ? [
                Btn(label: 'Duplicate as draft', icon: Icons.copy_outlined, onPressed: _duplicate),
                Btn(label: 'Delete', icon: Icons.delete_outline, variant: BtnVariant.danger, onPressed: _delete),
              ]
            : [
                Btn(label: 'Edit dates', icon: Icons.event_outlined, onPressed: _editDates),
                Btn(label: 'Discard', icon: Icons.delete_outline, variant: BtnVariant.danger, onPressed: _delete),
                Btn(label: 'Finalize', icon: Icons.check, variant: BtnVariant.accent, onPressed: _finalize),
              ],
      );
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: left),
          right,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 16), right]);
    });
  }

  Future<void> _commitTitle() async {
    final p = _plan!;
    final v = _titleCtrl.text.trim();
    setState(() => _editingTitle = false);
    await _save(p.copyWith(name: v.isEmpty ? null : v, nameExplicit: true));
  }

  Widget _mealToggles(MealPlan p) {
    final rt = context.rt;
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text('MEALS',
            style: RecipeTypography.mono(size: 10.5, color: rt.ink3, letterSpacing: 0.84)),
      ),
      for (final m in const ['Breakfast', 'Lunch', 'Dinner'])
        _MealChip(label: m, on: p.meals.contains(m), onTap: () => _toggleMeal(m)),
    ]);
  }

  Widget _layout(MealPlan p, bool readOnly) {
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth > 1100;
      final calendar = MealCalendar(
        plan: p,
        recipesById: _byId,
        collapsedDays: _collapsedDays,
        readOnly: readOnly,
        onCellTap: _pickCell,
        onRecipeTap: (r) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecipeDetailScreen(
            recipeId: r.id,
            recipesRepo: widget.recipesRepo,
            plansRepo: widget.plansRepo,
            plans: const [],
            uploadsRepo: widget.uploadsRepo,
            onChanged: widget.onChanged,
          ),
        )),
        onDayToggle: (di) => setState(() {
          if (_collapsedDays.contains(di)) {
            _collapsedDays.remove(di);
          } else {
            _collapsedDays.add(di);
          }
        }),
      );
      final cands = CandidatesPanel(
        candidates: p.candidates.map((id) => _byId[id]).whereType<Recipe>().toList(),
        readOnly: readOnly,
        onAdd: _addCandidate,
        onTapRecipe: (r) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecipeDetailScreen(
            recipeId: r.id,
            recipesRepo: widget.recipesRepo,
            plansRepo: widget.plansRepo,
            plans: const [],
            uploadsRepo: widget.uploadsRepo,
            onChanged: widget.onChanged,
          ),
        )),
        onRemove: (id) async {
          final next = List<String>.from(p.candidates)..remove(id);
          await _save(p.copyWith(candidates: next));
        },
      );
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: calendar),
          const SizedBox(width: 32),
          SizedBox(
            width: 320,
            child: cands,
          ),
        ]);
      }
      return Column(children: [
        calendar, const SizedBox(height: 24), cands,
      ]);
    });
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PlanStatus status;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final isFinal = status == PlanStatus.finalized;
    final color = isFinal ? rt.accentInk : rt.ink2;
    final bg = isFinal ? rt.accentSoft : rt.paper2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: isFinal ? rt.accent : rt.hair2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(isFinal ? 'FINALIZED' : 'DRAFT',
          style: RecipeTypography.mono(size: 11, color: color, letterSpacing: 0.66)),
    );
  }
}

class _MealChip extends StatelessWidget {
  const _MealChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? rt.ink : rt.paper,
          border: Border.all(color: on ? rt.ink : rt.hair2, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14, height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? rt.paper : Colors.transparent,
              border: Border.all(color: on ? rt.paper : rt.hair2),
            ),
            child: on ? Icon(Icons.check, size: 10, color: rt.ink) : null,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? rt.paper : rt.ink3)),
        ]),
      ),
    );
  }
}
