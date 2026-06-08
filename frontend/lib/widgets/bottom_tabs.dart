import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BottomTabsBar extends StatelessWidget {
  const BottomTabsBar({super.key, required this.current, required this.onNav});

  final int current;
  final ValueChanged<int> onNav;

  static const _items = [
    (icon: Icons.grid_view_outlined, label: 'Browse'),
    (icon: Icons.upload_outlined, label: 'Upload'),
    (icon: Icons.folder_outlined, label: 'Collections'),
    (icon: Icons.calendar_today_outlined, label: 'Plans'),
  ];

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
