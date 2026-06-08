import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';

/// Landing / sign-in screen. OAuth only — no email/password fields.
/// Shown by the root gate whenever there is no signed-in user.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authRepo,
    required this.onSignedIn,
  });

  final AuthRepository authRepo;
  final ValueChanged<User> onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn(Future<User> Function() method) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await method();
      if (!mounted) return;
      widget.onSignedIn(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Scaffold(
      backgroundColor: rt.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recipes',
                  textAlign: TextAlign.center,
                  style: RecipeTypography.serif(
                    size: 48,
                    weight: FontWeight.w500,
                    color: rt.ink,
                    letterSpacing: -0.96,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your recipe library, meal planner, and grocery list — '
                  'all in one place.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: rt.ink3, height: 1.4),
                ),
                const SizedBox(height: 40),
                _SignInButton(
                  icon: Icons.g_mobiledata,
                  label: 'Continue with Google',
                  enabled: !_busy,
                  onTap: () => _signIn(widget.authRepo.signInWithGoogle),
                ),
                const SizedBox(height: 12),
                _SignInButton(
                  icon: Icons.apple,
                  label: 'Continue with Apple',
                  enabled: !_busy,
                  onTap: () => _signIn(widget.authRepo.signInWithApple),
                ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: rt.accent,
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: rt.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Material(
      color: rt.paper,
      borderRadius: RecipeRadius.fieldBR,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: RecipeRadius.fieldBR,
        hoverColor: rt.paper2,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: rt.hair2),
            borderRadius: RecipeRadius.fieldBR,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: rt.ink),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: rt.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
