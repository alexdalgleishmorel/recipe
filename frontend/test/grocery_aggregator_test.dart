import 'package:flutter_test/flutter_test.dart';
import 'package:recipes/models/grocery_item.dart';
import 'package:recipes/models/ingredient.dart';
import 'package:recipes/models/recipe.dart';
import 'package:recipes/utils/grocery_aggregator.dart';

Recipe recipeWith(List<Ingredient> ings) => Recipe(
      id: 'r',
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
      ingredients: ings,
      instructions: const [],
    );

void main() {
  group('parseAmt', () {
    test('plain integer', () => expect(parseAmt('2'), 2));
    test('decimal', () => expect(parseAmt('1.5'), 1.5));
    test('fraction', () => expect(parseAmt('1/2'), 0.5));
    test('range takes leading number', () => expect(parseAmt('2-3'), 2));
    test('null', () => expect(parseAmt(null), isNull));
    test('non-numeric', () => expect(parseAmt('a pinch'), isNull));
  });

  group('formatAmt', () {
    test('integers', () => expect(formatAmt(2), '2'));
    test('1/2', () => expect(formatAmt(0.5), '1/2'));
    test('1.5', () => expect(formatAmt(1.5), '1.5'));
    test('null', () => expect(formatAmt(null), ''));
  });

  group('normUnit', () {
    test('lowercases', () => expect(normUnit('TBSP'), 'tbsp'));
    test('strips trailing dot', () => expect(normUnit('tbsp.'), 'tbsp'));
    test('null', () => expect(normUnit(null), ''));
  });

  group('categorize', () {
    test('chicken → protein', () => expect(categorize('chicken thighs'), GroceryCategory.protein));
    test('milk → dairy', () => expect(categorize('whole milk'), GroceryCategory.dairy));
    test('canned tomatoes → pantry not produce', () =>
        expect(categorize('canned tomatoes'), GroceryCategory.pantry));
    test('spinach → produce', () => expect(categorize('baby spinach'), GroceryCategory.produce));
    test('something weird → other', () => expect(categorize('unobtainium'), GroceryCategory.other));
  });

  group('aggregateIngredients', () {
    test('sums matching ingredients', () {
      final r1 = recipeWith(const [Ingredient(amount: '1', unit: 'tbsp', name: 'olive oil')]);
      final r2 = recipeWith(const [Ingredient(amount: '2', unit: 'tbsp', name: 'olive oil')]);
      final cats = aggregateIngredients([r1, r2]);
      final pantry = cats[GroceryCategory.pantry]!;
      final oil = pantry.firstWhere((i) => i.name == 'olive oil');
      expect(oil.amount, 3);
      expect(oil.unit, 'tbsp');
    });
    test('cannot sum across units → null amount', () {
      final r1 = recipeWith(const [Ingredient(amount: '1', unit: 'cup', name: 'flour')]);
      final r2 = recipeWith(const [Ingredient(amount: '100', unit: 'g', name: 'flour')]);
      final cats = aggregateIngredients([r1, r2]);
      final pantry = cats[GroceryCategory.pantry]!;
      final flours = pantry.where((i) => i.name == 'flour').toList();
      // Different units → two separate entries.
      expect(flours.length, 2);
    });
    test('groups by category', () {
      final r1 = recipeWith(const [
        Ingredient(amount: '1', unit: 'lb', name: 'chicken thighs'),
        Ingredient(amount: '2', unit: 'cups', name: 'spinach'),
        Ingredient(amount: '1', unit: 'tbsp', name: 'olive oil'),
      ]);
      final cats = aggregateIngredients([r1]);
      expect(cats[GroceryCategory.protein]!.length, 1);
      expect(cats[GroceryCategory.produce]!.length, 1);
      expect(cats[GroceryCategory.pantry]!.length, 1);
    });
  });
}
