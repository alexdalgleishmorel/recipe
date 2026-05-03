import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _searchableFields = [
  'title', 'description', 'cuisine', 'tags', 'dietary',
  'author', 'prepTime', 'cookTime', 'servings', 'ingredients.name',
];
const _exampleQueries = [
  'lasagna',
  'cuisine:(thai OR vietnamese)',
  'tags:weeknight AND dietary:vegetarian',
  'author:"Julia Child"',
  'prepTime:<30 AND servings:>=4',
  'cookware:cast-iron -dairy',
];

/// Datadog-style search bar — input + ? help popup + suggestions panel that
/// opens on focus. Submits the parsed query string back via [onChanged].
class DdSearch extends StatefulWidget {
  const DdSearch({super.key, required this.onChanged, this.initial = ''});
  final ValueChanged<String> onChanged;
  final String initial;

  @override
  State<DdSearch> createState() => _DdSearchState();
}

class _DdSearchState extends State<DdSearch> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  OverlayEntry? _panelEntry;
  OverlayEntry? _helpEntry;
  bool _showHelp = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    _removePanel();
    _removeHelp();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _showPanel();
    } else {
      // Defer so taps inside the panel can fire first.
      Future.delayed(const Duration(milliseconds: 150), _removePanel);
    }
  }

  void _showPanel() {
    if (_panelEntry != null) return;
    final overlay = Overlay.of(context);
    _panelEntry = OverlayEntry(builder: (ctx) {
      final rt = ctx.rt;
      return Positioned(
        width: 520,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 50),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: rt.paper,
                border: Border.all(color: rt.hair),
                borderRadius: RecipeRadius.cardBR,
                boxShadow: [BoxShadow(color: rt.modalShadow, blurRadius: 40, offset: const Offset(0, 12))],
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SecLabel('Searchable fields'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final f in _searchableFields) _FieldChip(label: f, onTap: () => _insert('$f:')),
                    _FieldChip(label: '<custom_tag_key>:', custom: true, onTap: () => _insert('cookware:')),
                  ]),
                  const SizedBox(height: 14),
                  _SecLabel('Example queries'),
                  const SizedBox(height: 4),
                  for (final q in _exampleQueries)
                    _ExampleRow(query: q, onTap: () { _ctrl.text = q; widget.onChanged(q); _removePanel(); _focus.unfocus(); }),
                ],
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_panelEntry!);
  }

  void _removePanel() {
    _panelEntry?.remove();
    _panelEntry = null;
  }

  void _toggleHelp() {
    if (_showHelp) {
      _removeHelp();
      return;
    }
    final overlay = Overlay.of(context);
    _helpEntry = OverlayEntry(builder: (ctx) {
      final rt = ctx.rt;
      const rows = [
        ('Free text', 'lasagna'),
        ('Attribute match', 'cuisine:italian'),
        ('Quoted value', 'author:"Julia Child"'),
        ('OR within attribute', 'cuisine:(thai OR vietnamese)'),
        ('Boolean AND / OR', 'tags:weeknight AND vegetarian'),
        ('Negation', '-dairy, -cuisine:french'),
        ('Numeric comparison', 'prepTime:<30, servings:>=4'),
        ('Custom key:value tag', 'cookware:cast-iron'),
      ];
      return Positioned(
        width: 420,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 50),
          followerAnchor: Alignment.topRight,
          targetAnchor: Alignment.bottomRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: rt.paper,
                border: Border.all(color: rt.hair),
                borderRadius: RecipeRadius.cardBR,
                boxShadow: [BoxShadow(color: rt.modalShadow, blurRadius: 40, offset: const Offset(0, 12))],
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Search syntax',
                      style: RecipeTypography.serif(size: 16, weight: FontWeight.w500, color: rt.ink)),
                  const SizedBox(height: 10),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 145,
                          child: Text(r.$1, style: TextStyle(fontSize: 12.5, color: rt.ink3)),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: rt.paper2, borderRadius: BorderRadius.circular(3)),
                            child: Text(r.$2,
                                style: RecipeTypography.mono(size: 12, color: rt.ink, letterSpacing: 0)),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_helpEntry!);
    setState(() => _showHelp = true);
  }

  void _removeHelp() {
    _helpEntry?.remove();
    _helpEntry = null;
    if (_showHelp) setState(() => _showHelp = false);
  }

  void _insert(String snippet) {
    final value = _ctrl.text;
    final next = value.isEmpty ? snippet : '$value $snippet';
    _ctrl.text = next;
    _ctrl.selection = TextSelection.collapsed(offset: next.length);
    widget.onChanged(next);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return CompositedTransformTarget(
      link: _link,
      child: Container(
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(color: rt.hair2),
          borderRadius: RecipeRadius.fieldBR,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: rt.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: widget.onChanged,
                style: RecipeTypography.mono(size: 13.5, color: rt.ink, letterSpacing: 0.135),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search e.g. chicken, cuisine:thai, prepTime:<30, tags:weeknight AND author:"Alex"',
                  hintStyle: RecipeTypography.mono(size: 13, color: rt.ink3, letterSpacing: 0),
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: _toggleHelp,
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 22, height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: rt.hair2),
                ),
                child: Text(
                  '?',
                  style: RecipeTypography.mono(size: 12, weight: FontWeight.w500, color: rt.ink3, letterSpacing: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecLabel extends StatelessWidget {
  const _SecLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Text(text.toUpperCase(),
        style: RecipeTypography.mono(size: 10.5, weight: FontWeight.w400, color: rt.ink3, letterSpacing: 0.84));
  }
}

class _FieldChip extends StatelessWidget {
  const _FieldChip({required this.label, required this.onTap, this.custom = false});
  final String label;
  final VoidCallback onTap;
  final bool custom;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(
            color: custom ? rt.accent : rt.hair,
            style: custom ? BorderStyle.solid : BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: RecipeTypography.mono(size: 12, color: custom ? rt.accentInk : rt.ink2, letterSpacing: 0)),
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({required this.query, required this.onTap});
  final String query;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        child: Text(query,
            style: RecipeTypography.mono(size: 12.5, color: rt.ink2, letterSpacing: 0)),
      ),
    );
  }
}

