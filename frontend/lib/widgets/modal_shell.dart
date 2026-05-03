import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'buttons.dart';

/// Shared modal scaffold (head/body/foot) used by every dialog in the app.
/// Mirrors `.modal` styling from Recipes.html.
class ModalShell extends StatelessWidget {
  const ModalShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.maxWidth = 460,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.of(context).size.height - 80,
        ),
        child: Material(
          color: rt.paper,
          borderRadius: RecipeRadius.cardBR,
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: rt.hair),
              borderRadius: RecipeRadius.cardBR,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rt.hair))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RecipeTypography.serif(size: 22, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.22)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: TextStyle(color: rt.ink3, fontSize: 13.5)),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                    child: child,
                  ),
                ),
                if (actions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                    decoration: BoxDecoration(
                      color: rt.paper2,
                      border: Border(top: BorderSide(color: rt.hair)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          actions[i],
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Show a modal with the recipes-themed backdrop and centered card.
Future<T?> showRecipeModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool barrierDismissible = true,
}) {
  final rt = Theme.of(context).extension<RecipeTheme>()!;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: rt.backdrop,
    useRootNavigator: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: builder(ctx),
    ),
  );
}

class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.label = 'Cancel'});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Btn(
      label: label,
      variant: BtnVariant.neutral,
      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
    );
  }
}
