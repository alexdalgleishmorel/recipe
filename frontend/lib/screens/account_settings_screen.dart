import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/page_head.dart';
import 'admin_users_screen.dart';

/// Account settings page. Surfaces the signed-in account's name/email plus the
/// app-level controls that used to live in the side nav: the dark-mode toggle,
/// the admin-only AI-import entitlement toggle (#6), and sign-out.
///
/// The AI-import toggle calls an async callback that flips `canAiImport` on the
/// current account (via AppShell, which rebuilds the whole tree with the
/// updated `User`). This screen keeps a local copy of `user` so it can reflect
/// the new entitlement immediately after the callback resolves.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.user,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSignOut,
    required this.onSetCanAiImport,
    required this.adminRepo,
  });

  final User user;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Future<void> Function() onSignOut;

  /// Admin-only toggle of the current account's `canAiImport` entitlement (#6).
  final Future<void> Function(bool) onSetCanAiImport;

  /// Backs the admin-only "Manage users" entry (#66), which lists all accounts
  /// and lets an admin flip each one's AI-import entitlement.
  final AdminRepository adminRepo;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late User _user = widget.user;
  bool _busyAi = false;

  @override
  void didUpdateWidget(AccountSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      _user = widget.user;
    }
  }

  Future<void> _toggleAi(bool value) async {
    if (_busyAi) return;
    setState(() => _busyAi = true);
    try {
      await widget.onSetCanAiImport(value);
      if (!mounted) return;
      setState(() => _user = _user.copyWith(canAiImport: value));
    } finally {
      if (mounted) setState(() => _busyAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return ContentScroll(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead(
            title: 'Account',
            subtitle: 'Manage your account and preferences',
          ),
          _SettingsCard(
            children: [
              Text(
                _user.displayName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: rt.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _user.email,
                style: TextStyle(fontSize: 13, color: rt.ink3),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: [
              _SettingRow(
                title: 'Dark mode',
                subtitle: widget.isDark ? 'On' : 'Off',
                control: _Toggle(value: widget.isDark, onChanged: (_) => widget.onToggleTheme()),
              ),
              if (_user.isAdmin) ...[
                Divider(height: 25, color: rt.hair),
                _SettingRow(
                  title: 'AI import',
                  subtitle: 'Admin entitlement for AI-assisted recipe import',
                  control: _Toggle(
                    value: _user.canAiImport,
                    onChanged: _busyAi ? null : _toggleAi,
                  ),
                ),
              ],
            ],
          ),
          if (_user.isAdmin) ...[
            const SizedBox(height: 16),
            _NavCard(
              title: 'Manage users',
              subtitle: 'Enable AI import for other accounts',
              icon: Icons.group_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminUsersScreen(adminRepo: widget.adminRepo),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SignOutButton(onSignOut: widget.onSignOut),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: rt.paper,
        borderRadius: RecipeRadius.cardBR,
        border: Border.all(color: rt.hair),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A tappable card row that navigates onward, styled like `_SettingsCard` with
/// a leading icon and a trailing chevron. Used for the admin "Manage users"
/// entry (#66).
class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Material(
      color: Colors.transparent,
      borderRadius: RecipeRadius.cardBR,
      child: InkWell(
        onTap: onTap,
        borderRadius: RecipeRadius.cardBR,
        hoverColor: rt.paper2,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: rt.paper,
            borderRadius: RecipeRadius.cardBR,
            border: Border.all(color: rt.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 18, color: rt.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: rt.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: rt.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, size: 18, color: rt.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.subtitle, required this.control});
  final String title;
  final String subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: rt.ink),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: rt.ink3)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        control,
      ],
    );
  }
}

/// Animated switch mirroring the wireframe `.tt-track`/`.tt-thumb` styling that
/// the side-nav toggles previously used. A null `onChanged` disables it.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color: value ? rt.accent : rt.hair,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: rt.hair2),
            ),
            child: Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: value ? 19 : 1,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: rt.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: rt.hair2),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onSignOut});
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Material(
      color: Colors.transparent,
      borderRadius: RecipeRadius.fieldBR,
      child: InkWell(
        onTap: () => onSignOut(),
        borderRadius: RecipeRadius.fieldBR,
        hoverColor: rt.paper2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: rt.hair),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 16, color: rt.danger),
              const SizedBox(width: 10),
              Text(
                'Sign out',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: rt.danger),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
