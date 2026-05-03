import 'custom_tag.dart';
import 'ingredient.dart';

class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.cuisine,
    required this.image,
    required this.description,
    required this.prepTime,
    required this.cookTime,
    required this.servings,
    required this.tags,
    required this.dietary,
    required this.author,
    required this.customTags,
    required this.ingredients,
    required this.instructions,
  });

  final String id;
  final String title;
  final String cuisine;
  final String image;
  final String description;
  final int prepTime;
  final int cookTime;
  final int servings;
  final List<String> tags;
  final List<String> dietary;
  final String author;
  final List<CustomTag> customTags;
  final List<Ingredient> ingredients;
  final List<String> instructions;

  int get totalTime => prepTime + cookTime;

  Recipe copyWith({
    String? id,
    String? title,
    String? cuisine,
    String? image,
    String? description,
    int? prepTime,
    int? cookTime,
    int? servings,
    List<String>? tags,
    List<String>? dietary,
    String? author,
    List<CustomTag>? customTags,
    List<Ingredient>? ingredients,
    List<String>? instructions,
  }) =>
      Recipe(
        id: id ?? this.id,
        title: title ?? this.title,
        cuisine: cuisine ?? this.cuisine,
        image: image ?? this.image,
        description: description ?? this.description,
        prepTime: prepTime ?? this.prepTime,
        cookTime: cookTime ?? this.cookTime,
        servings: servings ?? this.servings,
        tags: tags ?? this.tags,
        dietary: dietary ?? this.dietary,
        author: author ?? this.author,
        customTags: customTags ?? this.customTags,
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions ?? this.instructions,
      );

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        cuisine: (j['cuisine'] ?? '') as String,
        image: (j['image'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        prepTime: (j['prepTime'] as num?)?.toInt() ?? 0,
        cookTime: (j['cookTime'] as num?)?.toInt() ?? 0,
        servings: (j['servings'] as num?)?.toInt() ?? 0,
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        dietary: ((j['dietary'] as List?) ?? const []).map((e) => e.toString()).toList(),
        author: (j['author'] ?? 'Me') as String,
        customTags: ((j['customTags'] as List?) ?? const [])
            .map((e) => CustomTag.fromJson(e as Map<String, dynamic>))
            .toList(),
        ingredients: ((j['ingredients'] as List?) ?? const [])
            .map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        instructions: ((j['instructions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cuisine': cuisine,
        'image': image,
        'description': description,
        'prepTime': prepTime,
        'cookTime': cookTime,
        'servings': servings,
        'tags': tags,
        'dietary': dietary,
        'author': author,
        'customTags': customTags.map((c) => c.toJson()).toList(),
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'instructions': instructions,
      };

  static Recipe blank(String id) => Recipe(
        id: id,
        title: '',
        cuisine: '',
        image: '',
        description: '',
        prepTime: 0,
        cookTime: 0,
        servings: 1,
        tags: const [],
        dietary: const [],
        author: 'Me',
        customTags: const [],
        ingredients: const [],
        instructions: const [],
      );
}
