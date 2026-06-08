import 'dart:typed_data';

import '../models/collection.dart';
import '../models/incoming_share.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../models/share_item.dart';
import '../models/user.dart';

/// Storage abstraction for recipes. Today's only impl is `LocalRecipesRepository`
/// (shared_preferences). A future `HttpRecipesRepository` can implement this
/// same interface and be swapped in by changing one line in `main.dart`.
abstract class RecipesRepository {
  Future<List<Recipe>> list();
  Future<Recipe?> get(String id);
  Future<Recipe> save(Recipe recipe);
  Future<void> delete(String id);
}

abstract class MealPlansRepository {
  Future<List<MealPlan>> list();
  Future<MealPlan?> get(String id);
  Future<MealPlan> save(MealPlan plan);
  Future<void> delete(String id);
}

/// Named, reusable sets of recipe IDs. Same swap pattern as the others.
abstract class CollectionsRepository {
  Future<List<Collection>> list();
  Future<Collection?> get(String id);
  Future<Collection> save(Collection collection);
  Future<void> delete(String id);
}

/// User preferences (theme mode for now). Same swap pattern as the others.
abstract class SettingsRepository {
  Future<bool> isDark();
  Future<void> setDark(bool value);
}

/// Authentication. Today's only impl is `LocalAuthRepository` (a stub that
/// persists sign-in state in shared_preferences). A future
/// `CognitoAuthRepository` will implement this same interface and be swapped
/// in by changing one line in `main.dart`.
abstract class AuthRepository {
  /// The currently signed-in user, or null if signed out.
  Future<User?> currentUser();
  Future<User> signInWithGoogle();
  Future<void> signOut();

  /// Toggle the AI-import entitlement (#6) for the current account and return
  /// the updated user. This is the local approximation of the admin endpoint
  /// (#20); a real backend would scope this to admin callers.
  Future<User> setCanAiImport(bool value);
}

/// AI-assisted recipe import. Parses an uploaded file (PDF / image / text)
/// into a [Recipe] draft the user reviews before saving. This path is gated
/// behind the `canAiImport` entitlement (#6).
///
/// Today's only impl is `LocalRecipeImportService`, a stub that returns a
/// representative draft after a short delay.
abstract class RecipeImportService {
  /// Parse [bytes] (the picked file's contents, named [filename]) into a
  /// [Recipe] draft.
  Future<Recipe> parse({required Uint8List bytes, required String filename});
}

/// Sharing of recipes / collections as editable COPIES (fork-on-claim). Two
/// targeting modes: by recipient email, and by shareable link/token.
///
/// Real cross-user delivery is the backend's job (#24). Today's only impl is
/// `LocalSharingRepository`, a single-device stub that records shares so the
/// "Shared with me" flow is fully exercisable locally.
abstract class SharingRepository {
  /// Record a share targeted at [recipientEmail]. Delivery is the backend's
  /// concern; the local stub drops it into the inbox so the demo round-trips.
  Future<void> shareByEmail({
    required String recipientEmail,
    required ShareItem item,
  });

  /// Create a shareable link for [item] and return it. The link embeds a token
  /// that a recipient would claim via [claim].
  Future<String> createShareLink(ShareItem item);

  /// Pending (and recently claimed) shares for the current user's inbox.
  Future<List<IncomingShare>> listIncoming();

  /// Fork the shared item into the current user's library with brand-new ids,
  /// then mark the share claimed.
  Future<void> claim(String shareId);
}
