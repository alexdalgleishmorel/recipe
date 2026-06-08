import '../models/user.dart';
import 'http_api_client.dart';
import 'repositories.dart';

/// Live-backend implementation of [AdminRepository] against the admin
/// endpoints (#65). Both calls require an admin caller; the shared
/// [HttpApiClient] surfaces a 403 as an auth failure.
///
///  - [listUsers] → `GET /admin/users`
///  - [setEntitlement] → `POST /admin/entitlements {userId, canAiImport}`
class HttpAdminRepository implements AdminRepository {
  HttpAdminRepository(this._api);

  final HttpApiClient _api;

  @override
  Future<List<User>> listUsers() async {
    final data = await _api.getJson('/admin/users');
    final list = (data as List? ?? const []);
    return list.map((j) => User.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<User> setEntitlement(String userId, bool canAiImport) async {
    final data = await _api.postJson('/admin/entitlements', {
      'userId': userId,
      'canAiImport': canAiImport,
    });
    return User.fromJson(data as Map<String, dynamic>);
  }
}
