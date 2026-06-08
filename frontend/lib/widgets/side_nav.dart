import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/user.dart';
import '../theme/app_theme.dart';

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.current,
    required this.onNav,
    required this.user,
    required this.onOpenAccount,
  });

  final int current;
  final ValueChanged<int> onNav;
  final User user;

  /// Opens the account settings page (pushed onto the active tab's Navigator).
  final VoidCallback onOpenAccount;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final banner =
        isDark ? 'assets/brand/banner-dark.svg' : 'assets/brand/banner-light.svg';
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
            child: SvgPicture.asset(
              banner,
              width: 150,
              alignment: Alignment.centerLeft,
              semanticsLabel: 'Recipes',
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
            child: _AccountRow(user: user, onTap: onOpenAccount),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.user, required this.onTap});
  final User user;
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
                      'Account settings',
                      style: TextStyle(fontSize: 11, color: rt.ink3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.settings_outlined, size: 16, color: rt.ink3),
            ],
          ),
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
