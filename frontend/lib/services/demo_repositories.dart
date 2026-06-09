import 'dart:typed_data';

import '../models/collection.dart';
import '../models/incoming_share.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../models/share_item.dart';
import '../models/user.dart';
import '../utils/global_toast.dart';
import 'app_repositories.dart';
import 'local_admin_repository.dart';
import 'local_recipe_import_service.dart';
import 'local_settings_repository.dart';
import 'repositories.dart';
import 'seed_data.dart';

/// The synthetic, read-only portfolio demo account. Never authenticated and
/// never persisted — `AuthGate` enters a demo session locally.
final User demoUser = User(
  id: 'demo',
  email: 'demo@recipes.app',
  displayName: 'Demo',
  canAiImport: false,
  isAdmin: false,
  isDemo: true,
);

/// Thrown by every demo write to abort the calling handler's success path
/// (e.g. so no "Saved" toast fires). It is swallowed by the global error
/// handlers set in `main.dart` after [`showGlobalToast`] has already explained
/// the block, so it never surfaces as a crash.
class DemoWriteBlockedException implements Exception {
  const DemoWriteBlockedException();
  @override
  String toString() => 'DemoWriteBlockedException';
}

/// Surface the demo notice and abort. Used by every demo write method.
Never _blockDemoWrite() {
  showGlobalToast("Demo mode — changes aren't saved.");
  throw const DemoWriteBlockedException();
}

/// The repository set for a read-only demo session: real seed data for reads,
/// every write blocked. Reuses the local stubs for the pieces whose writes are
/// already unreachable in demo (admin UI hidden, import never persists, theme
/// is not data).
AppRepositories buildDemoRepositories() => AppRepositories(
      recipes: DemoRecipesRepository(),
      plans: DemoMealPlansRepository(),
      collections: DemoCollectionsRepository(),
      settings: LocalSettingsRepository(),
      // Unused in a demo session (AuthGate drives demo sign-in/out directly).
      auth: _UnusedDemoAuthRepository(),
      sharing: DemoSharingRepository(),
      importService: LocalRecipeImportService(),
      admin: LocalAdminRepository(),
      uploads: DemoUploadsRepository(),
    );

class DemoRecipesRepository implements RecipesRepository {
  List<Recipe>? _cache;
  Future<List<Recipe>> _seed() async => _cache ??= await SeedData.recipes();

  @override
  Future<List<Recipe>> list() async => List.of(await _seed());

  @override
  Future<Recipe?> get(String id) async {
    for (final r in await _seed()) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<Recipe> save(Recipe recipe) async => _blockDemoWrite();

  @override
  Future<void> delete(String id) async => _blockDemoWrite();
}

class DemoMealPlansRepository implements MealPlansRepository {
  List<MealPlan>? _cache;
  Future<List<MealPlan>> _seed() async => _cache ??= await SeedData.plans();

  @override
  Future<List<MealPlan>> list() async => List.of(await _seed());

  @override
  Future<MealPlan?> get(String id) async {
    for (final p in await _seed()) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<MealPlan> save(MealPlan plan) async => _blockDemoWrite();

  @override
  Future<void> delete(String id) async => _blockDemoWrite();
}

class DemoCollectionsRepository implements CollectionsRepository {
  List<Collection>? _cache;
  Future<List<Collection>> _seed() async =>
      _cache ??= await SeedData.collections();

  @override
  Future<List<Collection>> list() async => List.of(await _seed());

  @override
  Future<Collection?> get(String id) async {
    for (final c in await _seed()) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<Collection> save(Collection collection) async => _blockDemoWrite();

  @override
  Future<void> delete(String id) async => _blockDemoWrite();
}

class DemoUploadsRepository implements UploadsRepository {
  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String contentType,
  }) async =>
      _blockDemoWrite();
}

class DemoSharingRepository implements SharingRepository {
  @override
  Future<void> shareByEmail({
    required String recipientEmail,
    required ShareItem item,
  }) async =>
      _blockDemoWrite();

  @override
  Future<String> createShareLink(ShareItem item) async => _blockDemoWrite();

  @override
  Future<List<IncomingShare>> listIncoming() async => const [];

  @override
  Future<void> claim(String shareId) async => _blockDemoWrite();
}

/// Placeholder filling the [AppRepositories.auth] slot for the demo bundle.
/// `AuthGate` never calls it in a demo session, but the field is non-null.
class _UnusedDemoAuthRepository implements AuthRepository {
  @override
  Future<User?> currentUser() async => null;

  @override
  Future<User> signInWithGoogle() async => _blockDemoWrite();

  @override
  Future<void> signOut() async {}
}
