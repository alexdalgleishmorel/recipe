import 'package:flutter/material.dart';

import '../models/user.dart';
import '../theme/app_theme.dart';

class BottomTabsBar extends StatelessWidget {
  const BottomTabsBar({
    super.key,
    required this.current,
    required this.onNav,
    required this.user,
    required this.onSignOut,
  });

  final int current;
  final ValueChanged<int> onNav;
  final User user;
  final Future<void> Function() onSignOut;

  static const _items = [
    (icon: Icons.grid_view_outlined, label: 'Browse'),
    (icon: Icons.upload_outlined, label: 'Upload'),
    (icon: Icons.folder_outlined, label: 'Collections'),
    (icon: Icons.calendar_today_outlined, label: 'Plans'),
  ];

  Future<void> _openAccount(BuildContext context) async {
    final rt = context.rt;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: rt.paper,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: rt.ink,
                            ),
                          ),
                          Text(
                            user.email,
                            style: TextStyle(fontSize: 12, color: rt.ink3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: rt.hair),
              ListTile(
                leading: Icon(Icons.inbox_outlined, size: 20, color: rt.ink2),
                title: Text(
                  'Shared with me',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: rt.ink2,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onNav(4);
                },
              ),
              Divider(height: 1, color: rt.hair),
              ListTile(
                leading: Icon(Icons.logout, size: 20, color: rt.ink2),
                title: Text(
                  'Sign out',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: rt.ink2,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSignOut();
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border(top: BorderSide(color: rt.hair)),
      ),
      padding: EdgeInsets.only(
        top: 6, bottom: 6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _items.length; i++)
            _Tab(
              icon: _items[i].icon, label: _items[i].label,
              active: i == current, onTap: () => onNav(i),
            ),
          _Tab(
            icon: Icons.person_outline,
            label: 'Account',
            active: false,
            onTap: () => _openAccount(context),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final color = active ? rt.ink : rt.ink3;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
