import 'recipe.dart';

class Collection {
  Collection({
    required this.id,
    required this.name,
    required this.description,
    required this.recipeIds,
  });

  final String id;
  final String name;
  final String description;
  final List<String> recipeIds;

  /// Well-known id of the virtual, always-present "All Recipes" collection.
  /// Every user has it. It is derived from the full library at load time (see
  /// [Collection.allRecipes]) and never persisted, so it can't be renamed,
  /// deleted, shared, or have recipes added/removed by hand — a recipe is
  /// always in it by virtue of existing.
  static const String allRecipesId = 'all';

  bool get isAllRecipes => id == allRecipesId;

  /// The virtual "All Recipes" collection: every recipe in [recipes], in order.
  factory Collection.allRecipes(List<Recipe> recipes) => Collection(
        id: allRecipesId,
        name: 'All Recipes',
        description: 'Every recipe in your library.',
        recipeIds: [for (final r in recipes) r.id],
      );

  Collection copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? recipeIds,
  }) =>
      Collection(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        recipeIds: recipeIds ?? this.recipeIds,
      );

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        recipeIds: ((j['recipeIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'recipeIds': recipeIds,
      };

  static Collection blank(String id) => Collection(
        id: id,
        name: '',
        description: '',
        recipeIds: const [],
      );
}
