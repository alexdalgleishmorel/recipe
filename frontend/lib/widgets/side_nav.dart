import 'package:flutter/material.dart';

import '../models/user.dart';
import '../theme/app_theme.dart';
import 'theme_toggle.dart';

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.current,
    required this.onNav,
    required this.isDark,
    required this.onToggleTheme,
    required this.user,
    required this.onSignOut,
    required this.onSetCanAiImport,
    required this.onManageUsers,
  });

  final int current;
  final ValueChanged<int> onNav;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final User user;
  final Future<void> Function() onSignOut;

  /// Admin-only toggle of the current account's `canAiImport` entitlement (#6).
  final Future<void> Function(bool) onSetCanAiImport;

  /// Admin-only: open the Users management screen (#66).
  final VoidCallback onManageUsers;

  static const _items = [
    (icon: Icons.grid_view_outlined, label: 'Browse'),
    (icon: Icons.upload_outlined, label: 'Upload'),
    (icon: Icons.folder_outlined, label: 'Collections'),
    (icon: Icons.calendar_today_outlined, label: 'Meal Plans'),
    (icon: Icons.inbox_outlined, label: 'Shared with me'),
  ];

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border(right: BorderSide(color: rt.hair)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.only(bottom: 36, left: 4),
            child: Text(
              'Recipes',
              style: RecipeTypography.serif(size: 26, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.26),
            ),
          ),
          for (var i = 0; i < _items.length; i++)
            _NavItem(
              icon: _items[i].icon,
              label: _items[i].label,
              active: i == current,
              onTap: () => onNav(i),
            ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: rt.hair))),
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.isAdmin) ...[
                  _AdminAiToggle(
                    value: user.canAiImport,
                    onChanged: onSetCanAiImport,
                  ),
                  const SizedBox(height: 6),
                  _ManageUsersRow(onTap: onManageUsers),
                  const SizedBox(height: 6),
                ],
                ThemeToggle(isDark: isDark, onToggle: onToggleTheme),
                const SizedBox(height: 6),
                _AccountRow(user: user, onSignOut: onSignOut),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin-only entry that opens the Users management screen (#66). Styled like
/// `_AccountRow` — a quiet full-width row with a leading icon.
class _ManageUsersRow extends StatelessWidget {
  const _ManageUsersRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Material(
      color: Colors.transparent,
      borderRadius: RecipeRadius.fieldBR,
      child: InkWell(
        onTap: onTap,
        borderRadius: RecipeRadius.fieldBR,
        hoverColor: rt.paper2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.group_outlined, size: 16, color: rt.ink2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Manage users',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: rt.ink2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.user, required this.onSignOut});
  final User user;
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: rt.ink2,
                      ),
                    ),
                    Text(
                      'Sign out',
                      style: TextStyle(fontSize: 11, color: rt.ink3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.logout, size: 16, color: rt.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin-only switch for the AI-import entitlement (#6). Mirrors the
/// `ThemeToggle` track/thumb styling. Local stand-in for the admin endpoint
/// (#20) — toggles `canAiImport` on the current account.
class _AdminAiToggle extends StatelessWidget {
  const _AdminAiToggle({required this.value, required this.onChanged});
  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: RecipeRadius.fieldBR,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 18,
              decoration: BoxDecoration(
                color: value ? rt.accent : rt.hair,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: rt.hair2),
              ),
              child: Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: value ? 16 : 1,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 14,
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI IMPORT',
                overflow: TextOverflow.ellipsis,
                style: RecipeTypography.mono(
                  size: 11,
                  weight: FontWeight.w400,
                  color: rt.ink2,
                  letterSpacing: 0.66,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? rt.ink : Colors.transparent,
        borderRadius: RecipeRadius.fieldBR,
        child: InkWell(
          onTap: onTap,
          borderRadius: RecipeRadius.fieldBR,
          hoverColor: active ? null : rt.paper2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Icon(icon, size: 18, color: active ? rt.paper : rt.ink2),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: active ? rt.paper : rt.ink2,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
