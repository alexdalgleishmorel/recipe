/// The signed-in account. `canAiImport` and `isAdmin` are entitlement flags
/// that gate AI-import (#6) and sharing/admin UI (#5) respectively.
class User {
  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.canAiImport,
    required this.isAdmin,
  });

  final String id;
  final String email;
  final String displayName;
  final bool canAiImport;
  final bool isAdmin;

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? canAiImport,
    bool? isAdmin,
  }) =>
      User(
        id: id ?? this.id,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        canAiImport: canAiImport ?? this.canAiImport,
        isAdmin: isAdmin ?? this.isAdmin,
      );

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: (j['email'] ?? '') as String,
        displayName: (j['displayName'] ?? '') as String,
        canAiImport: (j['canAiImport'] as bool?) ?? false,
        isAdmin: (j['isAdmin'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'canAiImport': canAiImport,
        'isAdmin': isAdmin,
      };
}
