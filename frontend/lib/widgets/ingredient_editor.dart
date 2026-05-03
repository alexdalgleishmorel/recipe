import 'package:flutter/material.dart';

import '../models/ingredient.dart';
import '../theme/app_theme.dart';

class IngredientEditor extends StatefulWidget {
  const IngredientEditor({super.key, required this.ingredients, required this.onChanged});
  final List<Ingredient> ingredients;
  final ValueChanged<List<Ingredient>> onChanged;

  @override
  State<IngredientEditor> createState() => _IngredientEditorState();
}

class _IngredientEditorState extends State<IngredientEditor> {
  late List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.ingredients.map((i) => _Row.from(i)).toList();
  }

  void _emit() {
    widget.onChanged(_rows.map((r) => r.toIngredient()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 60,
                child: _input(_rows[i].amountCtrl, 'amt', () => _emit()),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 60,
                child: _input(_rows[i].unitCtrl, 'unit', () => _emit()),
              ),
              const SizedBox(width: 6),
              Expanded(child: _input(_rows[i].nameCtrl, 'ingredient', () => _emit())),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: rt.ink3),
                onPressed: () {
                  setState(() => _rows.removeAt(i));
                  _emit();
                },
              ),
            ]),
          ),
        InkWell(
          onTap: () {
            setState(() => _rows.add(_Row.empty()));
            _emit();
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: rt.hair2, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('+ add ingredient',
                style: RecipeTypography.mono(size: 12, color: rt.ink3, letterSpacing: 0.48)),
          ),
        ),
      ],
    );
  }

  Widget _input(TextEditingController ctrl, String hint, VoidCallback onChange) {
    final rt = context.rt;
    return TextField(
      controller: ctrl,
      onChanged: (_) => onChange(),
      style: TextStyle(fontSize: 13.5, color: rt.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: rt.ink3, fontSize: 13.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        isCollapsed: true,
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
    );
  }
}

class _Row {
  _Row.from(Ingredient i)
      : amountCtrl = TextEditingController(text: i.amount),
        unitCtrl = TextEditingController(text: i.unit),
        nameCtrl = TextEditingController(text: i.name);
  _Row.empty()
      : amountCtrl = TextEditingController(),
        unitCtrl = TextEditingController(),
        nameCtrl = TextEditingController();
  final TextEditingController amountCtrl;
  final TextEditingController unitCtrl;
  final TextEditingController nameCtrl;
  Ingredient toIngredient() => Ingredient(
        amount: amountCtrl.text,
        unit: unitCtrl.text,
        name: nameCtrl.text,
      );
}
