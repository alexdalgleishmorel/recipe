import '../models/user.dart';
import 'repositories.dart';

/// Default (mocked) implementation of [AdminRepository]. Returns a small,
/// in-memory roster so the admin Users screen is exercisable without a
/// backend. [setEntitlement] mutates the in-memory copy and returns the
/// updated user, mirroring the live endpoint's response shape.
class LocalAdminRepository implements AdminRepository {
  final List<User> _users = [
    User(
      id: 'demo-user',
      email: 'alex.dalgleishmorel@gmail.com',
      displayName: 'Alex',
      canAiImport: true,
      isAdmin: true,
    ),
    User(
      id: 'user-jordan',
      email: 'jordan.lee@example.com',
      displayName: 'Jordan Lee',
      canAiImport: false,
      isAdmin: false,
    ),
    User(
      id: 'user-sam',
      email: 'sam.rivera@example.com',
      displayName: 'Sam Rivera',
      canAiImport: true,
      isAdmin: false,
    ),
  ];

  @override
  Future<List<User>> listUsers() async => List.unmodifiable(_users);

  @override
  Future<User> setEntitlement(String userId, bool canAiImport) async {
    final i = _users.indexWhere((u) => u.id == userId);
    if (i == -1) {
      throw StateError('No such user: $userId');
    }
    final updated = _users[i].copyWith(canAiImport: canAiImport);
    _users[i] = updated;
    return updated;
  }
}
