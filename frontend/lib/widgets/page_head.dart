import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RecipeTypography.serif(size: 42, weight: FontWeight.w500, color: rt.ink, letterSpacing: -0.84, height: 1.05),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: TextStyle(color: rt.ink3, fontSize: 14)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class ContentScroll extends StatelessWidget {
  const ContentScroll({super.key, required this.child, this.maxWidth = 1400});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 80),
            child: child,
          ),
        ),
      ),
    );
  }
}
