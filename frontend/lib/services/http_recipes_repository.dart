import '../models/recipe.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [RecipesRepository] against `/recipes`.
///
/// Mirrors [LocalRecipesRepository]'s contract; the only meaningful difference
/// is in [save], which routes to `POST /recipes` for not-yet-persisted recipes
/// (server assigns the id) and `PUT /recipes/{id}` for existing ones.
///
/// A recipe is treated as "new" when its id is empty or still carries a
/// client-generated prefix (see [_isClientId]) — i.e. the server has never
/// seen it. The persisted recipe (with its server-assigned id) is returned.
class HttpRecipesRepository implements RecipesRepository {
  HttpRecipesRepository(this._api);

  final HttpApiClient _api;

  @override
  Future<List<Recipe>> list() async {
    final data = await _api.getJson('/recipes');
    final list = (data as List? ?? const []);
    return list
        .map((j) => Recipe.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Recipe?> get(String id) async {
    final data = await _api.getJson('/recipes/$id');
    if (data == null) return null;
    return Recipe.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<Recipe> save(Recipe recipe) async {
    final body = recipe.toJson();
    if (_isClientId(recipe.id)) {
      body.remove('id');
      final data = await _api.postJson('/recipes', body);
      return Recipe.fromJson(data as Map<String, dynamic>);
    }
    final data = await _api.putJson('/recipes/${recipe.id}', body);
    return Recipe.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) => _api.delete('/recipes/$id');

  /// True when the id is empty or a locally minted id (`r-...`, `recipe-...`),
  /// meaning the server has not assigned one yet → POST instead of PUT.
  static bool _isClientId(String id) =>
      id.isEmpty || id.startsWith('r-') || id.startsWith('recipe-');
}
