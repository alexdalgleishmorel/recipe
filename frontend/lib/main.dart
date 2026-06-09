import 'dart:async';

import 'package:flutter/material.dart';

import 'services/app_repositories.dart';
import 'services/cognito_auth_repository.dart';
import 'services/demo_repositories.dart';
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
import 'utils/global_toast.dart';
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

/// Build the real (authenticated) repository set for the current mode.
AppRepositories _buildRealRepositories() {
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
    return AppRepositories(
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
  return AppRepositories(
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
  // The read-only demo blocks writes by throwing [DemoWriteBlockedException]
  // (after toasting). Run the app inside a guarded zone — and initialise the
  // binding inside it via runApp — so async errors from button handlers land
  // here. Swallow the demo block (the toast already explained it) so a blocked
  // write quietly aborts the handler; re-report everything else.
  runZonedGuarded(() {
    final defaultFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is DemoWriteBlockedException) return;
      defaultFlutterOnError?.call(details);
    };

    final real = _buildRealRepositories();
    final demo = buildDemoRepositories();
    runApp(RecipesApp(realRepos: real, demoRepos: demo));
  }, (error, stack) {
    if (error is DemoWriteBlockedException) return;
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
  });
}

class RecipesApp extends StatefulWidget {
  const RecipesApp({
    super.key,
    required this.realRepos,
    required this.demoRepos,
  });

  /// The authenticated repository set (local or backend, per [useBackend]).
  final AppRepositories realRepos;

  /// The read-only, seeded repository set used by the demo session.
  final AppRepositories demoRepos;

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
    final isDark = await widget.realRepos.settings.isDark();
    if (!mounted) return;
    setState(() => _dark = isDark);
  }

  Future<void> _toggleTheme() async {
    setState(() => _dark = !_dark);
    await widget.realRepos.settings.setDark(_dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipes',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: globalMessengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: AuthGate(
        realRepos: widget.realRepos,
        demoRepos: widget.demoRepos,
        isDark: _dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
