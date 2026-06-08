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
