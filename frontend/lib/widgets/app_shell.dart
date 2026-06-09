import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart';
import '../models/user.dart';
import '../screens/account_settings_screen.dart';
import '../screens/browse_screen.dart';
import '../screens/collections_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/shared_with_me_screen.dart';
import '../screens/upload_screen.dart';
import '../services/app_repositories.dart';
import '../theme/app_theme.dart';
import 'bottom_tabs.dart';
import 'side_nav.dart';

const kDesktopBreakpoint = 760.0;

/// Top-level shell. Owns the loaded recipe + plan lists, the active tab,
/// and the per-tab Navigator (so deep navigation preserves tab state).
/// Mutations from screens call back via the various `on*` callbacks.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.user,
    required this.repos,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSignOut,
  });

  /// The signed-in user. Issues read `user.isAdmin` (#5 sharing),
  /// `user.canAiImport` (#6 gated import), and `user.isDemo` (read-only demo
  /// banner) to gate UI.
  final User user;

  /// The active repository bundle (authenticated or demo).
  final AppRepositories repos;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onSignOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  List<Recipe> _recipes = const [];
  List<MealPlan> _plans = const [];
  List<Collection> _collections = const [];
  bool _loading = true;
  String? _error;

  final _navKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        widget.repos.recipes.list(),
        widget.repos.plans.list(),
        widget.repos.collections.list(),
      ]);
      if (!mounted) return;
      final recipes = results[0] as List<Recipe>;
      setState(() {
        _recipes = recipes;
        _plans = results[1] as List<MealPlan>;
        // Pin the virtual "All Recipes" collection (every recipe, always
        // current) ahead of the persisted ones. It is derived here, never
        // stored — see [Collection.allRecipes].
        _collections = [
          Collection.allRecipes(recipes),
          ...results[2] as List<Collection>,
        ];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openAccount() {
    _navKeys[_tab].currentState?.push(MaterialPageRoute(
      builder: (_) => AccountSettingsScreen(
        user: widget.user,
        isDark: widget.isDark,
        onToggleTheme: widget.onToggleTheme,
        onSignOut: widget.onSignOut,
        adminRepo: widget.repos.admin,
      ),
    ));
  }

  void _onNav(int i) {
    if (i == _tab) {
      // Tap-again pops to root.
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  Widget _tabRoot(int tab) {
    if (tab == 0) {
      return BrowseScreen(
        recipes: _recipes,
        recipesRepo: widget.repos.recipes,
        plansRepo: widget.repos.plans,
        plans: _plans,
        collectionsRepo: widget.repos.collections,
        collections: _collections,
        sharingRepo: widget.repos.sharing,
        uploadsRepo: widget.repos.uploads,
        onChanged: _refresh,
      );
    }
    if (tab == 1) {
      return UploadScreen(
        user: widget.user,
        recipesRepo: widget.repos.recipes,
        importService: widget.repos.importService,
        uploadsRepo: widget.repos.uploads,
        onChanged: _refresh,
      );
    }
    if (tab == 2) {
      return CollectionsScreen(
        collections: _collections,
        recipes: _recipes,
        plans: _plans,
        collectionsRepo: widget.repos.collections,
        recipesRepo: widget.repos.recipes,
        plansRepo: widget.repos.plans,
        sharingRepo: widget.repos.sharing,
        uploadsRepo: widget.repos.uploads,
        onChanged: _refresh,
      );
    }
    if (tab == 3) {
      return PlansScreen(
        plans: _plans,
        recipes: _recipes,
        plansRepo: widget.repos.plans,
        recipesRepo: widget.repos.recipes,
        uploadsRepo: widget.repos.uploads,
        onChanged: _refresh,
      );
    }
    return SharedWithMeScreen(
      sharingRepo: widget.repos.sharing,
      onChanged: _refresh,
    );
  }

  /// Persistent disclaimer shown across the top in the read-only demo session.
  Widget _demoBanner(RecipeTheme rt) {
    return Material(
      color: rt.accentSoft,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 15, color: rt.accentInk),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Demo account — explore freely, but changes won\'t be saved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: rt.accentInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigator(int tab) {
    return Navigator(
      key: _navKeys[tab],
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => _tabRoot(tab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (_loading) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: rt.accent),
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: rt.ink)),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: rt.ink3)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;
        final content = IndexedStack(
          index: _tab,
          children: [
            _buildNavigator(0),
            _buildNavigator(1),
            _buildNavigator(2),
            _buildNavigator(3),
            _buildNavigator(4),
          ],
        );

        if (isDesktop) {
          return Scaffold(
            backgroundColor: rt.paper,
            body: Column(
              children: [
                if (widget.user.isDemo) _demoBanner(rt),
                Expanded(
                  child: Row(
                    children: [
                      SideNav(
                        current: _tab,
                        onNav: _onNav,
                        user: widget.user,
                        onOpenAccount: _openAccount,
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: rt.paper,
          body: Column(
            children: [
              if (widget.user.isDemo) _demoBanner(rt),
              Expanded(child: content),
              BottomTabsBar(
                current: _tab,
                onNav: _onNav,
                user: widget.user,
                onOpenAccount: _openAccount,
              ),
            ],
          ),
        );
      },
    );
  }
}
