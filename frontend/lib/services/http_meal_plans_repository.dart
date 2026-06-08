import '../models/meal_plan.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [MealPlansRepository] against `/plans`.
/// See [HttpRecipesRepository] for the new-vs-existing [save] convention.
class HttpMealPlansRepository implements MealPlansRepository {
  HttpMealPlansRepository(this._api);

  final HttpApiClient _api;

  @override
  Future<List<MealPlan>> list() async {
    final data = await _api.getJson('/plans');
    final list = (data as List? ?? const []);
    return list
        .map((j) => MealPlan.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<MealPlan?> get(String id) async {
    final data = await _api.getJson('/plans/$id');
    if (data == null) return null;
    return MealPlan.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<MealPlan> save(MealPlan plan) async {
    final body = plan.toJson();
    if (_isClientId(plan.id)) {
      body.remove('id');
      final data = await _api.postJson('/plans', body);
      return MealPlan.fromJson(data as Map<String, dynamic>);
    }
    final data = await _api.putJson('/plans/${plan.id}', body);
    return MealPlan.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) => _api.delete('/plans/$id');

  static bool _isClientId(String id) =>
      id.isEmpty || id.startsWith('p-') || id.startsWith('plan-');
}
