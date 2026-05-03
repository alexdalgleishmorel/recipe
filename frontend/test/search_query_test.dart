import 'package:flutter_test/flutter_test.dart';
import 'package:recipes/models/custom_tag.dart';
import 'package:recipes/models/ingredient.dart';
import 'package:recipes/models/recipe.dart';
import 'package:recipes/utils/search_query.dart';

Recipe r({
  String id = 'r',
  String title = '',
  String cuisine = '',
  String description = '',
  int prepTime = 0,
  int cookTime = 0,
  int servings = 1,
  List<String> tags = const [],
  List<String> dietary = const [],
  String author = 'Me',
  List<CustomTag> customTags = const [],
  List<Ingredient> ingredients = const [],
}) =>
    Recipe(
      id: id,
      title: title,
      cuisine: cuisine,
      image: '',
      description: description,
      prepTime: prepTime,
      cookTime: cookTime,
      servings: servings,
      tags: tags,
      dietary: dietary,
      author: author,
      customTags: customTags,
      ingredients: ingredients,
      instructions: const [],
    );

void main() {
  group('parseSearchQuery', () {
    test('empty query matches everything', () {
      expect(parseSearchQuery('')(r(title: 'anything')), isTrue);
      expect(parseSearchQuery('   ')(r()), isTrue);
    });

    test('free text searches title/description/ingredients', () {
      final pred = parseSearchQuery('lasagna');
      expect(pred(r(title: 'Mom\'s Lasagna')), isTrue);
      expect(pred(r(description: 'A baked lasagna casserole')), isTrue);
      expect(pred(r(ingredients: [const Ingredient(amount: '1', unit: 'sheet', name: 'lasagna sheet')])), isTrue);
      expect(pred(r(title: 'risotto')), isFalse);
    });

    test('attribute match exact', () {
      final pred = parseSearchQuery('cuisine:italian');
      expect(pred(r(cuisine: 'Italian')), isTrue);
      expect(pred(r(cuisine: 'Mexican')), isFalse);
    });

    test('quoted value preserves spaces', () {
      final pred = parseSearchQuery('author:"Julia Child"');
      expect(pred(r(author: 'Julia Child')), isTrue);
      expect(pred(r(author: 'Julia')), isFalse);
    });

    test('OR within attribute', () {
      final pred = parseSearchQuery('cuisine:(thai OR vietnamese)');
      expect(pred(r(cuisine: 'Thai')), isTrue);
      expect(pred(r(cuisine: 'Vietnamese')), isTrue);
      expect(pred(r(cuisine: 'Italian')), isFalse);
    });

    test('boolean AND', () {
      final pred = parseSearchQuery('tags:weeknight AND dietary:vegetarian');
      expect(pred(r(tags: const ['weeknight'], dietary: const ['vegetarian'])), isTrue);
      expect(pred(r(tags: const ['weeknight'])), isFalse);
      expect(pred(r(dietary: const ['vegetarian'])), isFalse);
    });

    test('boolean OR', () {
      final pred = parseSearchQuery('cuisine:thai OR cuisine:italian');
      expect(pred(r(cuisine: 'Thai')), isTrue);
      expect(pred(r(cuisine: 'Italian')), isTrue);
      expect(pred(r(cuisine: 'Mexican')), isFalse);
    });

    test('negation', () {
      final pred = parseSearchQuery('-cuisine:french');
      expect(pred(r(cuisine: 'French')), isFalse);
      expect(pred(r(cuisine: 'Italian')), isTrue);
    });

    test('numeric comparisons', () {
      expect(parseSearchQuery('prepTime:<30')(r(prepTime: 25)), isTrue);
      expect(parseSearchQuery('prepTime:<30')(r(prepTime: 30)), isFalse);
      expect(parseSearchQuery('servings:>=4')(r(servings: 4)), isTrue);
      expect(parseSearchQuery('servings:>=4')(r(servings: 3)), isFalse);
      expect(parseSearchQuery('cookTime:<=15')(r(cookTime: 15)), isTrue);
    });

    test('custom tag match', () {
      final pred = parseSearchQuery('cookware:cast-iron');
      expect(pred(r(customTags: const [CustomTag(key: 'cookware', value: 'cast-iron')])), isTrue);
      expect(pred(r(customTags: const [CustomTag(key: 'cookware', value: 'wok')])), isFalse);
    });

    test('mixed query', () {
      final pred = parseSearchQuery('cuisine:italian prepTime:<20');
      expect(pred(r(cuisine: 'Italian', prepTime: 10)), isTrue);
      expect(pred(r(cuisine: 'Italian', prepTime: 30)), isFalse);
      expect(pred(r(cuisine: 'Mexican', prepTime: 10)), isFalse);
    });
  });
}
