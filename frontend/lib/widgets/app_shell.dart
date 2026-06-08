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
import '../services/repositories.dart';
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
    required this.recipesRepo,
    required this.plansRepo,
    required this.collectionsRepo,
    required this.sharingRepo,
    required this.importService,
    required this.adminRepo,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSignOut,
    required this.onSetCanAiImport,
  });

  /// The signed-in user. Later issues read `user.isAdmin` (#5 sharing) and
  /// `user.canAiImport` (#6 gated import) to gate UI.
  final User user;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final CollectionsRepository collectionsRepo;
  final SharingRepository sharingRepo;
  final RecipeImportService importService;
  final AdminRepository adminRepo;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onSignOut;

  /// Admin-only toggle of the current account's `canAiImport` entitlement (#6).
  /// Local approximation of the admin endpoint (#20).
  final Future<void> Function(bool) onSetCanAiImport;

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
        widget.recipesRepo.list(),
        widget.plansRepo.list(),
        widget.collectionsRepo.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _recipes = results[0] as List<Recipe>;
        _plans = results[1] as List<MealPlan>;
        _collections = results[2] as List<Collection>;
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
        onSetCanAiImport: widget.onSetCanAiImport,
        adminRepo: widget.adminRepo,
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
        recipesRepo: widget.recipesRepo,
        plansRepo: widget.plansRepo,
        plans: _plans,
        collectionsRepo: widget.collectionsRepo,
        collections: _collections,
        sharingRepo: widget.sharingRepo,
        onChanged: _refresh,
      );
    }
    if (tab == 1) {
      return UploadScreen(
        user: widget.user,
        recipesRepo: widget.recipesRepo,
        importService: widget.importService,
        onChanged: _refresh,
      );
    }
    if (tab == 2) {
      return CollectionsScreen(
        collections: _collections,
        recipes: _recipes,
        plans: _plans,
        collectionsRepo: widget.collectionsRepo,
        recipesRepo: widget.recipesRepo,
        plansRepo: widget.plansRepo,
        sharingRepo: widget.sharingRepo,
        onChanged: _refresh,
      );
    }
    if (tab == 3) {
      return PlansScreen(
        plans: _plans,
        recipes: _recipes,
        plansRepo: widget.plansRepo,
        recipesRepo: widget.recipesRepo,
        onChanged: _refresh,
      );
    }
    return SharedWithMeScreen(
      sharingRepo: widget.sharingRepo,
      onChanged: _refresh,
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
            body: Row(
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
          );
        }
        return Scaffold(
          backgroundColor: rt.paper,
          body: Column(
            children: [
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
