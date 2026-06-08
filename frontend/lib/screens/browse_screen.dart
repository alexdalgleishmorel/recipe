import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../utils/search_query.dart';
import '../widgets/dd_search.dart';
import '../widgets/page_head.dart';
import '../widgets/pagination.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.recipes,
    required this.recipesRepo,
    required this.plansRepo,
    required this.plans,
    required this.collectionsRepo,
    required this.collections,
    required this.onChanged,
  });

  final List<Recipe> recipes;
  final List<MealPlan> plans;
  final List<Collection> collections;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final CollectionsRepository collectionsRepo;
  final Future<void> Function() onChanged;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _query = '';
  int _page = 1;

  static const _pageSize = 12;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final pred = parseSearchQuery(_query);
    final filtered = widget.recipes.where(pred).toList();
    final total = filtered.length;
    final totalPages = (total / _pageSize).ceil().clamp(1, 999);
    final safePage = _page.clamp(1, totalPages);
    final start = (safePage - 1) * _pageSize;
    final slice = filtered.sublist(start, (start + _pageSize).clamp(0, total));

    return ContentScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead(
            title: 'Browse',
            subtitle: 'Your library of ${widget.recipes.length} recipes',
          ),
          DdSearch(
            initial: _query,
            onChanged: (q) => setState(() {
              _query = q;
              _page = 1;
            }),
          ),
          const SizedBox(height: 24),
          if (slice.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No recipes match your search.',
                style: TextStyle(color: rt.ink3, fontSize: 14),
              ),
            )
          else
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth < 600
                  ? 2
                  : c.maxWidth < 900
                      ? 2
                      : c.maxWidth < 1280
                          ? 3
                          : 4;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: slice.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (_, i) {
                  final r = slice[i];
                  return RecipeCard(
                    recipe: r,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RecipeDetailScreen(
                        recipeId: r.id,
                        recipesRepo: widget.recipesRepo,
                        plansRepo: widget.plansRepo,
                        plans: widget.plans,
                        collectionsRepo: widget.collectionsRepo,
                        collections: widget.collections,
                        onChanged: widget.onChanged,
                      ),
                    )),
                  );
                },
              );
            }),
          Pagination(
            page: safePage,
            totalPages: totalPages,
            startIdx: start,
            shownCount: slice.length,
            total: total,
            onPage: (p) => setState(() => _page = p),
          ),
        ],
      ),
    );
  }
}
