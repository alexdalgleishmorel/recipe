import 'repositories.dart';

/// The fully-wired set of repositories for one session "mode". Built once in
/// `main.dart` (real, per `useBackend`) and once for the read-only demo
/// (`buildDemoRepositories` in `demo_repositories.dart`), then carried through
/// `AuthGate` → `AppShell` so the widget tree stays mode-agnostic.
class AppRepositories {
  const AppRepositories({
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
