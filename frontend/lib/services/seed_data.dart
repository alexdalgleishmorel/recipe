import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';

/// Loads the bundled JSON seed (24 recipes + 2 plans) extracted verbatim from
/// the Recipes.html wireframe. Used by the local repositories on first launch
/// to populate empty storage.
class SeedData {
  static Future<List<Recipe>> recipes() async {
    final raw = await rootBundle.loadString('assets/seed/recipes.json');
    final list = jsonDecode(raw) as List;
    return list.map((j) => Recipe.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<MealPlan>> plans() async {
    final raw = await rootBundle.loadString('assets/seed/plans.json');
    final list = jsonDecode(raw) as List;
    return list.map((j) => MealPlan.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<Collection>> collections() async {
    final raw = await rootBundle.loadString('assets/seed/collections.json');
    final list = jsonDecode(raw) as List;
    return list.map((j) => Collection.fromJson(j as Map<String, dynamic>)).toList();
  }
}
