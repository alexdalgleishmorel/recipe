import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class InstructionEditor extends StatefulWidget {
  const InstructionEditor({super.key, required this.steps, required this.onChanged});
  final List<String> steps;
  final ValueChanged<List<String>> onChanged;

  @override
  State<InstructionEditor> createState() => _InstructionEditorState();
}

class _InstructionEditorState extends State<InstructionEditor> {
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.steps.map((s) => TextEditingController(text: s)).toList();
  }

  void _emit() => widget.onChanged(_ctrls.map((c) => c.text).toList());

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _ctrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 10),
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: RecipeTypography.mono(
                      size: 13, weight: FontWeight.w500, color: rt.accentInk, letterSpacing: 0.52,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrls[i],
                    onChanged: (_) => _emit(),
                    minLines: 2,
                    maxLines: 6,
                    style: TextStyle(fontSize: 15.5, color: rt.ink2, height: 1.6),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: rt.hair2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: rt.hair2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: rt.accent),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: rt.ink3),
                  onPressed: () {
                    setState(() => _ctrls.removeAt(i));
                    _emit();
                  },
                ),
              ],
            ),
          ),
        InkWell(
          onTap: () {
            setState(() => _ctrls.add(TextEditingController()));
            _emit();
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: rt.hair2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('+ add step',
                style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0.48)),
          ),
        ),
      ],
    );
  }
}
