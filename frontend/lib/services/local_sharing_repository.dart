import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/incoming_share.dart';
import '../models/share_item.dart';
import '../utils/id_gen.dart';
import 'repositories.dart';

/// Single-device stub for [SharingRepository]. Because there is no backend yet,
/// "sharing" can't actually cross users — so for the demo every share is
/// dropped straight into the current user's own "Shared with me" inbox, where
/// it can be claimed (forked) into the library. This makes all UI flows
/// round-trip locally.
///
/// Claiming performs the fork: it deep-copies the recipe (or the collection
/// AND each of its recipes) into the library via the injected recipes /
/// collections repos with fresh ids, then marks the share claimed.
///
// TODO(#24): replace with HttpSharingRepository (real cross-user delivery).
class LocalSharingRepository implements SharingRepository {
  LocalSharingRepository({
    required this.recipesRepo,
    required this.collectionsRepo,
  });

  final RecipesRepository recipesRepo;
  final CollectionsRepository collectionsRepo;

  static const _key = 'shares.incoming.v1';
  static const _linkBase = 'https://recipes.app/share';

  Future<List<IncomingShare>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((j) => IncomingShare.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(List<IncomingShare> shares) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(shares.map((s) => s.toJson()).toList()),
    );
  }

  @override
  Future<void> shareByEmail({
    required String recipientEmail,
    required ShareItem item,
  }) async {
    final shares = await _read();
    shares.add(IncomingShare(
      id: newId('share'),
      item: item,
      fromEmail: recipientEmail,
      sharedAt: DateTime.now(),
    ));
    await _write(shares);
  }

  @override
  Future<String> createShareLink(ShareItem item) async {
    final token = newId('tok');
    final shares = await _read();
    shares.add(IncomingShare(
      id: newId('share'),
      item: item,
      fromEmail: 'link',
      sharedAt: DateTime.now(),
      token: token,
    ));
    await _write(shares);
    return '$_linkBase/$token';
  }

  @override
  Future<List<IncomingShare>> listIncoming() async {
    final shares = await _read();
    shares.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
    return shares;
  }

  @override
  Future<void> claim(String shareId) async {
    final shares = await _read();
    final idx = shares.indexWhere((s) => s.id == shareId);
    if (idx < 0) return;
    final share = shares[idx];
    if (share.claimed) return;

    switch (share.item.type) {
      case ShareItemType.recipe:
        await _forkRecipe(share.item.id);
        break;
      case ShareItemType.collection:
        await _forkCollection(share.item.id);
        break;
    }

    shares[idx] = share.copyWith(claimed: true);
    await _write(shares);
  }

  /// Deep-copy a single recipe with a new id; returns the new id (or null if
  /// the source no longer exists).
  Future<String?> _forkRecipe(String sourceId) async {
    final source = await recipesRepo.get(sourceId);
    if (source == null) return null;
    final copy = source.copyWith(id: newId('recipe'));
    await recipesRepo.save(copy);
    return copy.id;
  }

  /// Deep-copy a collection AND each of its recipes, rewriting the recipe ids
  /// so the forked collection points at the forked recipes.
  Future<void> _forkCollection(String sourceId) async {
    final source = await collectionsRepo.get(sourceId);
    if (source == null) return;
    final newRecipeIds = <String>[];
    for (final recipeId in source.recipeIds) {
      final newId = await _forkRecipe(recipeId);
      if (newId != null) newRecipeIds.add(newId);
    }
    final copy = source.copyWith(
      id: newId('collection'),
      recipeIds: newRecipeIds,
    );
    await collectionsRepo.save(copy);
  }
}
