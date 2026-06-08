import 'package:flutter/material.dart';

import '../models/user.dart';
import '../screens/login_screen.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';

/// Root gate. Resolves the current user on boot and shows `LoginScreen` when
/// signed out, `AppShell` once signed in. Sign-out from the shell returns here.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authRepo,
    required this.recipesRepo,
    required this.plansRepo,
    required this.collectionsRepo,
    required this.sharingRepo,
    required this.isDark,
    required this.onToggleTheme,
  });

  final AuthRepository authRepo;
  final RecipesRepository recipesRepo;
  final MealPlansRepository plansRepo;
  final CollectionsRepository collectionsRepo;
  final SharingRepository sharingRepo;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final user = await widget.authRepo.currentUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  void _onSignedIn(User user) => setState(() => _user = user);

  Future<void> _signOut() async {
    await widget.authRepo.signOut();
    if (!mounted) return;
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (_loading) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: rt.accent),
          ),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return LoginScreen(
        authRepo: widget.authRepo,
        onSignedIn: _onSignedIn,
      );
    }

    return AppShell(
      user: user,
      recipesRepo: widget.recipesRepo,
      plansRepo: widget.plansRepo,
      collectionsRepo: widget.collectionsRepo,
      sharingRepo: widget.sharingRepo,
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
      onSignOut: _signOut,
    );
  }
}
