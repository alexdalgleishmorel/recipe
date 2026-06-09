import 'package:flutter/material.dart';

import '../models/user.dart';
import '../screens/login_screen.dart';
import '../services/app_repositories.dart';
import '../services/demo_repositories.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';

/// Root gate. Resolves the current user on boot and shows `LoginScreen` when
/// signed out, `AppShell` once signed in. Sign-out from the shell returns here.
///
/// Also owns the read-only **demo session**: choosing the demo (from the login
/// screen, including the sign-in failure path) swaps to the seeded
/// [AppRepositories.demoRepos] and a synthetic [demoUser] without touching
/// auth — so it works even in the backend build.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.realRepos,
    required this.demoRepos,
    required this.isDark,
    required this.onToggleTheme,
  });

  final AppRepositories realRepos;
  final AppRepositories demoRepos;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  bool _demo = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.realRepos.auth.currentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (e) {
      // Never leave the gate stuck on a spinner: surface the failure so it can
      // be retried (and so the cause is visible) instead of hanging forever.
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onSignedIn(User user) => setState(() => _user = user);

  void _enterDemo() => setState(() => _demo = true);

  Future<void> _signOut() async {
    // A demo session has no real auth state — just drop back to the gate.
    if (_demo) {
      setState(() {
        _demo = false;
        _user = null;
      });
      return;
    }
    await widget.realRepos.auth.signOut();
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

    // A chosen demo session takes precedence over (the absence of) a real user.
    if (_demo) {
      return AppShell(
        user: demoUser,
        repos: widget.demoRepos,
        isDark: widget.isDark,
        onToggleTheme: widget.onToggleTheme,
        onSignOut: _signOut,
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: rt.paper,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sign-in failed',
                    style: RecipeTypography.serif(
                      size: 24,
                      weight: FontWeight.w500,
                      color: rt.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: rt.ink3, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _resolve,
                    child: const Text('Try again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _enterDemo,
                    child: const Text('Explore the demo instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return LoginScreen(
        authRepo: widget.realRepos.auth,
        onSignedIn: _onSignedIn,
        onEnterDemo: _enterDemo,
      );
    }

    return AppShell(
      user: user,
      repos: widget.realRepos,
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
      onSignOut: _signOut,
    );
  }
}
