import 'package:flutter/material.dart';

import 'services/cognito_auth_repository.dart';
import 'services/http_admin_repository.dart';
import 'services/http_api_client.dart';
import 'services/http_collections_repository.dart';
import 'services/http_meal_plans_repository.dart';
import 'services/http_recipe_import_service.dart';
import 'services/http_recipes_repository.dart';
import 'services/http_sharing_repository.dart';
import 'services/http_uploads_repository.dart';
import 'services/local_admin_repository.dart';
import 'services/local_auth_repository.dart';
import 'services/local_collections_repository.dart';
import 'services/local_meal_plans_repository.dart';
import 'services/local_recipe_import_service.dart';
import 'services/local_recipes_repository.dart';
import 'services/local_settings_repository.dart';
import 'services/local_sharing_repository.dart';
import 'services/local_uploads_repository.dart';
import 'services/repositories.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';

/// Compile-time switch between the local (mocked) stack and the live backend.
///
/// Default `false` keeps `flutter test`, local dev, and the current Pages build
/// running entirely on the `Local*` repositories. Enable with
/// `--dart-define=USE_BACKEND=true` (plus `--dart-define=API_BASE_URL=...` and
/// the Cognito config, which already default to the deployed stack).
const bool useBackend = bool.fromEnvironment('USE_BACKEND', defaultValue: false);

/// API origin for the live backend. Defaults match the deployed stack; mirrors
/// the default baked into [CognitoAuthRepository].
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://yz0jib3efa.execute-api.us-east-1.amazonaws.com',
);

/// The fully-wired set of repositories for a given mode. Built once by
/// [_buildRepos] so the widget tree below stays mode-agnostic.
class _Repos {
  _Repos({
    required this.recipes,
    required this.plans,
    required this.collections,
    required this.settings,
    required this.auth,
    required this.sharing,
    required this.importService,
    required this.admin,
    required this.uploads,
  });

  final RecipesRepository recipes;
  final MealPlansRepository plans;
  final CollectionsRepository collections;
  final SettingsRepository settings;
  final AuthRepository auth;
  final SharingRepository sharing;
  final RecipeImportService importService;
  final AdminRepository admin;
  final UploadsRepository uploads;
}

_Repos _buildRepos() {
  // Settings stay local in both modes.
  final SettingsRepository settings = LocalSettingsRepository();

  if (useBackend) {
    final auth = CognitoAuthRepository();
    final api = HttpApiClient(
      baseUrl: apiBaseUrl,
      tokenProvider: auth.currentIdToken,
    );
    final recipes = HttpRecipesRepository(api);
    final collections = HttpCollectionsRepository(api);
    // Real cross-user delivery + server-side fork (#24).
    final sharing = HttpSharingRepository(api);
    // Real Anthropic-backed AI import (#19/#25).
    final importService = HttpRecipeImportService(api);
    return _Repos(
      recipes: recipes,
      plans: HttpMealPlansRepository(api),
      collections: collections,
      settings: settings,
      auth: auth,
      sharing: sharing,
      importService: importService,
      admin: HttpAdminRepository(api),
      uploads: HttpUploadsRepository(api),
    );
  }

  // RecipeImportService stays a local stub in default (mocked) mode.
  final RecipeImportService importService = LocalRecipeImportService();

  final recipes = LocalRecipesRepository();
  final collections = LocalCollectionsRepository();
  return _Repos(
    recipes: recipes,
    plans: LocalMealPlansRepository(),
    collections: collections,
    settings: settings,
    auth: LocalAuthRepository(),
    sharing: LocalSharingRepository(
      recipesRepo: recipes,
      collectionsRepo: collections,
    ),
    importService: importService,
    admin: LocalAdminRepository(),
    uploads: LocalUploadsRepository(),
  );
}

void main() {
  final repos = _buildRepos();
  runApp(RecipesApp(
    recipesRepo: repos.recipes,
    plansRepo: repos.plans,
    collectionsRepo: repos.collections,
    settingsRepo: repos.settings,
    authRepo: repos.auth,
    sharingRepo: repos.sharing,
    importService: repos.importService,
    adminRepo: repos.admin,
    uploadsRepo: repos.uploads,
  ));
}

class RecipesApp extends StatefulWidget {
  const RecipesApp({
    super.key,
    required this.recipesRepo,
    required this.plansRepo,
    required this.collectionsRepo,
    required this.settingsRepo,
    required this.authRepo,
    required this.sharingRepo,
    required this.importService,
    required this.adminRepo,
    required this.uploadsRepo,
  });

  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final CollectionsRepository collectionsRepo;
  final SettingsRepository settingsRepo;
  final AuthRepository authRepo;
  final SharingRepository sharingRepo;
  final RecipeImportService importService;
  final AdminRepository adminRepo;
  final UploadsRepository uploadsRepo;

  @override
  State<RecipesApp> createState() => _RecipesAppState();
}

class _RecipesAppState extends State<RecipesApp> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDark = await widget.settingsRepo.isDark();
    if (!mounted) return;
    setState(() => _dark = isDark);
  }

  Future<void> _toggleTheme() async {
    setState(() => _dark = !_dark);
    await widget.settingsRepo.setDark(_dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipes',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: AuthGate(
        authRepo: widget.authRepo,
        recipesRepo: widget.recipesRepo,
        plansRepo: widget.plansRepo,
        collectionsRepo: widget.collectionsRepo,
        sharingRepo: widget.sharingRepo,
        importService: widget.importService,
        adminRepo: widget.adminRepo,
        uploadsRepo: widget.uploadsRepo,
        isDark: _dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
