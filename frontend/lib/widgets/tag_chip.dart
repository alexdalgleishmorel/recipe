import 'package:flutter/material.dart';

import '../models/custom_tag.dart';
import '../theme/app_theme.dart';

/// Key:value tag chip — `.tchip-kv` from Recipes.html. Dashed border by default;
/// solid green-tinted variant for dietary tags (`tchip-diet`).
class KvTagChip extends StatelessWidget {
  const KvTagChip({super.key, required this.tag, this.onRemove, this.dietary = false});
  final CustomTag tag;
  final VoidCallback? onRemove;
  final bool dietary;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    final borderColor = dietary
        ? Color.alphaBlend(rt.ok.withValues(alpha: 0.35), rt.paper)
        : rt.accent;
    final bg = dietary
        ? Color.alphaBlend(rt.ok.withValues(alpha: 0.12), rt.paper)
        : Colors.transparent;
    final keyColor = dietary
        ? Color.alphaBlend(rt.ok.withValues(alpha: 0.7), rt.ink)
        : rt.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(
          color: borderColor,
          style: dietary ? BorderStyle.solid : BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag.key,
              style: RecipeTypography.mono(size: 12, weight: FontWeight.w500, color: keyColor, letterSpacing: 0)),
          Text(':', style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0)),
          Text(tag.value,
              style: RecipeTypography.mono(size: 12, color: rt.ink, letterSpacing: 0)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 11, color: rt.ink3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
