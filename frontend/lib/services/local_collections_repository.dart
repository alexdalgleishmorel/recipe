import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection.dart';
import 'repositories.dart';
import 'seed_data.dart';

class LocalCollectionsRepository implements CollectionsRepository {
  static const _key = 'collections.v1';

  Future<List<Collection>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final seeded = await SeedData.collections();
      await _write(seeded);
      return seeded;
    }
    final list = jsonDecode(raw) as List;
    return list.map((j) => Collection.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> _write(List<Collection> collections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(collections.map((c) => c.toJson()).toList()));
  }

  @override
  Future<List<Collection>> list() => _read();

  @override
  Future<Collection?> get(String id) async {
    final all = await _read();
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Collection> save(Collection collection) async {
    final all = await _read();
    final idx = all.indexWhere((c) => c.id == collection.id);
    if (idx >= 0) {
      all[idx] = collection;
    } else {
      all.add(collection);
    }
    await _write(all);
    return collection;
  }

  @override
  Future<void> delete(String id) async {
    final all = await _read();
    all.removeWhere((c) => c.id == id);
    await _write(all);
  }
}
