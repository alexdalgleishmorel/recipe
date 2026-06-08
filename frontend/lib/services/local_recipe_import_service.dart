import 'dart:typed_data';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import 'repositories.dart';

/// Stub AI import. Stands in for the real Bedrock-backed parser until #19/#23:
/// it ignores the uploaded bytes and returns a representative parsed draft
/// after a short delay so the review-and-save flow is fully exercisable.
///
// TODO(#19/#23): replace with HttpRecipeImportService (Bedrock).
class LocalRecipeImportService implements RecipeImportService {
  @override
  Future<Recipe> parse({required Uint8List bytes, required String filename}) async {
    // Simulate the latency of a remote vision/extraction pass.
    await Future.delayed(const Duration(milliseconds: 1800));
    return Recipe(
      id: 'staging',
      title: "Mom's Sunday Lasagna",
      cuisine: 'Italian',
      image: '',
      description:
          'A bolognese lasagna with fresh pasta sheets, slow-cooked sauce, and a creamy béchamel. Best made the day before.',
      prepTime: 30,
      cookTime: 90,
      servings: 8,
      tags: const ['family', 'sunday'],
      dietary: const [],
      author: 'Me',
      customTags: const [],
      ingredients: const [
        Ingredient(amount: '1', unit: 'lb', name: 'fresh lasagna sheets'),
        Ingredient(amount: '2', unit: 'lb', name: 'ground beef + pork mix'),
        Ingredient(amount: '1', unit: 'qt', name: 'whole tomatoes'),
        Ingredient(amount: '1', unit: 'cup', name: 'béchamel'),
        Ingredient(amount: '300', unit: 'g', name: 'mozzarella'),
      ],
      instructions: const [
        'Brown the meat in olive oil with a soffritto until deeply colored.',
        'Add tomatoes; simmer 90 minutes until thick.',
        'Make the béchamel; season with nutmeg.',
        'Layer pasta, sauce, béchamel, and mozzarella in a deep dish.',
        'Bake at 375°F for 35 minutes; rest 15 before slicing.',
      ],
    );
  }
}
