import 'package:flutter/material.dart';

import 'services/local_auth_repository.dart';
import 'services/local_collections_repository.dart';
import 'services/local_meal_plans_repository.dart';
import 'services/local_recipe_import_service.dart';
import 'services/local_recipes_repository.dart';
import 'services/local_settings_repository.dart';
import 'services/local_sharing_repository.dart';
import 'services/repositories.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';

void main() {
  // Repositories — swap these implementations for `HttpRecipesRepository`
  // (etc.) once a backend exists. Nothing else needs to change.
  final RecipesRepository recipesRepo = LocalRecipesRepository();
  final MealPlansRepository plansRepo = LocalMealPlansRepository();
  final CollectionsRepository collectionsRepo = LocalCollectionsRepository();
  final SettingsRepository settingsRepo = LocalSettingsRepository();
  final AuthRepository authRepo = LocalAuthRepository();
  final SharingRepository sharingRepo = LocalSharingRepository(
    recipesRepo: recipesRepo,
    collectionsRepo: collectionsRepo,
  );
  // Swap for `HttpRecipeImportService` (Bedrock) once #19/#23 land.
  final RecipeImportService importService = LocalRecipeImportService();

  runApp(RecipesApp(
    recipesRepo: recipesRepo,
    plansRepo: plansRepo,
    collectionsRepo: collectionsRepo,
    settingsRepo: settingsRepo,
    authRepo: authRepo,
    sharingRepo: sharingRepo,
    importService: importService,
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
  });

  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final CollectionsRepository collectionsRepo;
  final SettingsRepository settingsRepo;
  final AuthRepository authRepo;
  final SharingRepository sharingRepo;
  final RecipeImportService importService;

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
        isDark: _dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
