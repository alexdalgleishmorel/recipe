import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';

/// Storage abstraction for recipes. Today's only impl is `LocalRecipesRepository`
/// (shared_preferences). A future `HttpRecipesRepository` can implement this
/// same interface and be swapped in by changing one line in `main.dart`.
abstract class RecipesRepository {
  Future<List<Recipe>> list();
  Future<Recipe?> get(String id);
  Future<Recipe> save(Recipe recipe);
  Future<void> delete(String id);
}

abstract class MealPlansRepository {
  Future<List<MealPlan>> list();
  Future<MealPlan?> get(String id);
  Future<MealPlan> save(MealPlan plan);
  Future<void> delete(String id);
}

/// Named, reusable sets of recipe IDs. Same swap pattern as the others.
abstract class CollectionsRepository {
  Future<List<Collection>> list();
  Future<Collection?> get(String id);
  Future<Collection> save(Collection collection);
  Future<void> delete(String id);
}

/// User preferences (theme mode for now). Same swap pattern as the others.
abstract class SettingsRepository {
  Future<bool> isDark();
  Future<void> setDark(bool value);
}
