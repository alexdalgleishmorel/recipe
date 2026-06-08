import '../models/collection.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [CollectionsRepository] against
/// `/collections`. See [HttpRecipesRepository] for the new-vs-existing [save]
/// convention.
class HttpCollectionsRepository implements CollectionsRepository {
  HttpCollectionsRepository(this._api);

  final HttpApiClient _api;

  @override
  Future<List<Collection>> list() async {
    final data = await _api.getJson('/collections');
    final list = (data as List? ?? const []);
    return list
        .map((j) => Collection.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Collection?> get(String id) async {
    final data = await _api.getJson('/collections/$id');
    if (data == null) return null;
    return Collection.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<Collection> save(Collection collection) async {
    final body = collection.toJson();
    if (_isClientId(collection.id)) {
      body.remove('id');
      final data = await _api.postJson('/collections', body);
      return Collection.fromJson(data as Map<String, dynamic>);
    }
    final data = await _api.putJson('/collections/${collection.id}', body);
    return Collection.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) => _api.delete('/collections/$id');

  static bool _isClientId(String id) =>
      id.isEmpty || id.startsWith('c-') || id.startsWith('collection-');
}
