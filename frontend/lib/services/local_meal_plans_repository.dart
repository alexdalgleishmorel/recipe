import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_plan.dart';
import 'repositories.dart';
import 'seed_data.dart';

class LocalMealPlansRepository implements MealPlansRepository {
  static const _key = 'plans.v1';

  Future<List<MealPlan>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final seeded = await SeedData.plans();
      await _write(seeded);
      return seeded;
    }
    final list = jsonDecode(raw) as List;
    return list.map((j) => MealPlan.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> _write(List<MealPlan> plans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(plans.map((p) => p.toJson()).toList()));
  }

  @override
  Future<List<MealPlan>> list() => _read();

  @override
  Future<MealPlan?> get(String id) async {
    final all = await _read();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<MealPlan> save(MealPlan plan) async {
    final all = await _read();
    final idx = all.indexWhere((p) => p.id == plan.id);
    if (idx >= 0) {
      all[idx] = plan;
    } else {
      all.add(plan);
    }
    await _write(all);
    return plan;
  }

  @override
  Future<void> delete(String id) async {
    final all = await _read();
    all.removeWhere((p) => p.id == id);
    await _write(all);
  }
}
