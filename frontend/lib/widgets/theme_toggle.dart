import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Sidebar-foot theme toggle. Mirrors `.theme-toggle`/`.tt-track`/`.tt-thumb`
/// styling from the wireframe — animated track + thumb plus a `LIGHT`/`DARK`
/// mono label.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, required this.isDark, required this.onToggle});
  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onToggle,
      borderRadius: RecipeRadius.fieldBR,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34, height: 18,
              decoration: BoxDecoration(
                color: isDark ? rt.accent : rt.hair,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: rt.hair2),
              ),
              child: Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: isDark ? 16 : 1,
                  top: 0,
                  child: Container(
                    width: 14, height: 14,
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
            Text(
              isDark ? 'DARK' : 'LIGHT',
              style: RecipeTypography.mono(size: 11, weight: FontWeight.w400, color: rt.ink2, letterSpacing: 0.66),
            ),
          ],
        ),
      ),
    );
  }
}
