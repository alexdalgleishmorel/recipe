import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BtnVariant { neutral, primary, accent, danger, dangerSolid, ghost }
enum BtnSize { md, sm, icon }

/// Recipe-styled button — port of the `.btn` family from Recipes.html.
class Btn extends StatelessWidget {
  const Btn({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = BtnVariant.neutral,
    this.size = BtnSize.md,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BtnVariant variant;
  final BtnSize size;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final disabled = onPressed == null;

    Color bg;
    Color fg;
    Color border;

    switch (variant) {
      case BtnVariant.neutral:
        bg = rt.paper; fg = rt.ink; border = rt.hair2; break;
      case BtnVariant.primary:
        bg = rt.ink; fg = rt.paper; border = rt.ink; break;
      case BtnVariant.accent:
        bg = rt.accent; fg = Colors.white; border = rt.accent; break;
      case BtnVariant.danger:
        bg = rt.paper; fg = rt.danger; border = rt.hair2; break;
      case BtnVariant.dangerSolid:
        bg = rt.danger; fg = Colors.white; border = rt.danger; break;
      case BtnVariant.ghost:
        bg = Colors.transparent; fg = rt.ink2; border = Colors.transparent; break;
    }

    EdgeInsets padding;
    double textSize;
    double iconSize;
    switch (size) {
      case BtnSize.md:
        padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 9); textSize = 14; iconSize = 14; break;
      case BtnSize.sm:
        padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 6); textSize = 13; iconSize = 13; break;
      case BtnSize.icon:
        padding = EdgeInsets.zero; textSize = 14; iconSize = 14; break;
    }

    Widget child;
    if (size == BtnSize.icon) {
      child = SizedBox(
        width: 32, height: 32,
        child: Icon(icon, size: 16, color: fg),
      );
    } else {
      child = Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: fg),
              const SizedBox(width: 8),
            ],
            Text(label, style: TextStyle(color: fg, fontSize: textSize, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: RecipeRadius.fieldBR,
        child: InkWell(
          onTap: onPressed,
          borderRadius: RecipeRadius.fieldBR,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: RecipeRadius.fieldBR,
              border: Border.all(color: border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Generic card container — used for plan cards, candidate panel, etc.
class SurfaceBox extends StatelessWidget {
  const SurfaceBox({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Container(
      decoration: BoxDecoration(
        color: rt.paper,
        border: Border.all(color: rt.hair),
        borderRadius: borderRadius ?? RecipeRadius.cardBR,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Small mono-styled label, matching `.dd-sec-label`/`.tags-label`.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Text(
      text.toUpperCase(),
      style: RecipeTypography.mono(size: 10.5, weight: FontWeight.w500, color: color ?? rt.ink3, letterSpacing: 0.85),
    );
  }
}
