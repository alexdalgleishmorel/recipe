import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import 'repositories.dart';
import 'seed_data.dart';

class LocalRecipesRepository implements RecipesRepository {
  static const _key = 'recipes.v1';

  Future<List<Recipe>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final seeded = await SeedData.recipes();
      await _write(seeded);
      return seeded;
    }
    final list = jsonDecode(raw) as List;
    return list.map((j) => Recipe.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> _write(List<Recipe> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(recipes.map((r) => r.toJson()).toList()));
  }

  @override
  Future<List<Recipe>> list() => _read();

  @override
  Future<Recipe?> get(String id) async {
    final all = await _read();
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<Recipe> save(Recipe recipe) async {
    final all = await _read();
    final idx = all.indexWhere((r) => r.id == recipe.id);
    if (idx >= 0) {
      all[idx] = recipe;
    } else {
      all.add(recipe);
    }
    await _write(all);
    return recipe;
  }

  @override
  Future<void> delete(String id) async {
    final all = await _read();
    all.removeWhere((r) => r.id == id);
    await _write(all);
  }
}
