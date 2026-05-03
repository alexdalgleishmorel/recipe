import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class Pagination extends StatelessWidget {
  const Pagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.startIdx,
    required this.shownCount,
    required this.total,
    required this.onPage,
  });

  final int page; // 1-based
  final int totalPages;
  final int startIdx; // 0-based
  final int shownCount;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    if (totalPages <= 1) return const SizedBox.shrink();

    final pages = <int?>[]; // null = ellipsis
    void add(int p) => pages.add(p);
    if (totalPages <= 7) {
      for (var i = 1; i <= totalPages; i++) {
        add(i);
      }
    } else {
      add(1);
      if (page > 3) pages.add(null);
      for (var i = (page - 1).clamp(2, totalPages - 1); i <= (page + 1).clamp(2, totalPages - 1); i++) {
        add(i);
      }

      if (page < totalPages - 2) pages.add(null);
      add(totalPages);
    }

    return Container(
      margin: const EdgeInsets.only(top: 36),
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: rt.hair))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${startIdx + 1}–${startIdx + shownCount} OF $total',
            style: RecipeTypography.mono(size: 11.5, color: rt.ink3, letterSpacing: 0.69),
          ),
          Row(
            children: [
              _PageBtn(
                label: '‹',
                disabled: page <= 1,
                onTap: () => onPage(page - 1),
              ),
              for (final p in pages)
                if (p == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: rt.ink3)),
                  )
                else
                  _PageBtn(
                    label: '$p',
                    active: p == page,
                    onTap: () => onPage(p),
                  ),
              _PageBtn(
                label: '›',
                disabled: page >= totalPages,
                onTap: () => onPage(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  const _PageBtn({required this.label, required this.onTap, this.active = false, this.disabled = false});
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: RecipeRadius.fieldBR,
        child: Container(
          height: 34,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? rt.ink : Colors.transparent,
            border: Border.all(color: active ? rt.ink : Colors.transparent),
            borderRadius: RecipeRadius.fieldBR,
          ),
          child: Text(
            label,
            style: RecipeTypography.mono(
              size: 13,
              color: active ? rt.paper : (disabled ? rt.ink3 : rt.ink2),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
