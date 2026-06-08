import 'package:flutter/material.dart';

import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/modals/new_plan_modal.dart';
import '../widgets/page_head.dart';
import '../widgets/plan_card.dart';
import '../widgets/toast.dart';
import 'plan_detail_screen.dart';

enum _SortKey { dateDesc, dateAsc, titleAsc, titleDesc }

class PlansScreen extends StatefulWidget {
  const PlansScreen({
    super.key,
    required this.plans,
    required this.recipes,
    required this.plansRepo,
    required this.recipesRepo,
    required this.onChanged,
    this.uploadsRepo,
  });

  final List<MealPlan> plans;
  final List<Recipe> recipes;
  final MealPlansRepository plansRepo;
  final RecipesRepository recipesRepo;
  final Future<void> Function() onChanged;
  final UploadsRepository? uploadsRepo;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String _query = '';
  _SortKey _sort = _SortKey.dateDesc;
  bool _showFinalized = false;

  Future<void> _newPlan() async {
    final p = await openNewPlanModal(context);
    if (p == null) return;
    // Use the saved plan's id: the backend assigns its own id on create, so
    // navigating with the pre-save (client) id would 404 ("not found").
    final saved = await widget.plansRepo.save(p);
    await widget.onChanged();
    if (!mounted) return;
    showToast(context, 'Draft created');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlanDetailScreen(
        planId: saved.id,
        plansRepo: widget.plansRepo,
        recipesRepo: widget.recipesRepo,
        uploadsRepo: widget.uploadsRepo,
        onChanged: widget.onChanged,
      ),
    ));
  }

  List<MealPlan> _filtered() {
    final q = _query.trim().toLowerCase();
    var list = widget.plans.where((p) {
      final s = p.status == PlanStatus.finalized;
      if (s != _showFinalized) return false;
      if (q.isEmpty) return true;
      return p.displayName.toLowerCase().contains(q) ||
          p.start.toLowerCase().contains(q) ||
          p.end.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case _SortKey.dateDesc:
          return b.start.compareTo(a.start);
        case _SortKey.dateAsc:
          return a.start.compareTo(b.start);
        case _SortKey.titleAsc:
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        case _SortKey.titleDesc:
          return b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase());
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final draftCount = widget.plans.where((p) => p.status == PlanStatus.draft).length;
    final finalCount = widget.plans.where((p) => p.status == PlanStatus.finalized).length;
    final list = _filtered();

    return ContentScroll(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead(
          title: 'Meal Plans',
          subtitle: 'Sketch a week, gather candidates, finalize when ready',
          trailing: Btn(
            label: 'New plan',
            icon: Icons.add,
            variant: BtnVariant.primary,
            onPressed: _newPlan,
          ),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search plans by name or date',
                hintStyle: TextStyle(color: rt.ink3),
                prefixIcon: Icon(Icons.search, size: 18, color: rt.ink3),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.hair)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.hair)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: rt.accent)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text('SORT', style: RecipeTypography.mono(size: 11, color: rt.ink3, letterSpacing: 0.88)),
          const SizedBox(width: 8),
          DropdownButton<_SortKey>(
            value: _sort,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: _SortKey.dateDesc, child: Text('Date · newest')),
              DropdownMenuItem(value: _SortKey.dateAsc, child: Text('Date · oldest')),
              DropdownMenuItem(value: _SortKey.titleAsc, child: Text('Title · A→Z')),
              DropdownMenuItem(value: _SortKey.titleDesc, child: Text('Title · Z→A')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? _SortKey.dateDesc),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rt.hair))),
          child: Row(children: [
            _Tab(label: 'Drafts', count: draftCount, active: !_showFinalized, onTap: () => setState(() => _showFinalized = false)),
            _Tab(label: 'Finalized', count: finalCount, active: _showFinalized, onTap: () => setState(() => _showFinalized = true)),
          ]),
        ),
        const SizedBox(height: 18),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              widget.plans.isEmpty
                  ? 'No meal plans yet — create one to get started.'
                  : 'No matches.',
              style: TextStyle(color: rt.ink3, fontSize: 14),
            ),
          )
        else
          Column(
            children: [
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PlanCard(
                    plan: p,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PlanDetailScreen(
                        planId: p.id,
                        plansRepo: widget.plansRepo,
                        recipesRepo: widget.recipesRepo,
                        uploadsRepo: widget.uploadsRepo,
                        onChanged: widget.onChanged,
                      ),
                    )),
                  ),
                ),
            ],
          ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.count, required this.active, required this.onTap});
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Container(
          padding: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? rt.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14, color: active ? rt.ink : rt.ink3, fontWeight: FontWeight.w500)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: rt.paper2, borderRadius: BorderRadius.circular(4)),
              child: Text('$count',
                  style: RecipeTypography.mono(size: 11, color: active ? rt.ink : rt.ink3, letterSpacing: 0)),
            ),
          ]),
        ),
      ),
    );
  }
}
