import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_format.dart';

/// Two side-by-side date boxes (start / end) backed by the platform date
/// picker, with mutual validation: moving the end before the start (or the
/// start after the end) nudges the other by a week. Shared by the New Plan and
/// Edit Dates modals so the date-range UX is identical.
class DateRangeField extends StatelessWidget {
  const DateRangeField({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onChanged;

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final first = DateTime.now().subtract(const Duration(days: 90));
    final last = DateTime.now().add(const Duration(days: 730));
    // Clamp into the picker's allowed window so a plan whose stored range falls
    // outside it still opens (showDatePicker asserts initialDate is in range).
    var initial = isStart ? start : end;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (result == null) return;
    var s = start, e = end;
    if (isStart) {
      s = result;
      if (e.isBefore(s)) e = s.add(const Duration(days: 6));
    } else {
      e = result;
      if (e.isBefore(s)) s = e.subtract(const Duration(days: 6));
    }
    onChanged(s, e);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _DateBox(
          label: formatMonthDay(start),
          onTap: () => _pick(context, isStart: true),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _DateBox(
          label: formatMonthDay(end),
          onTap: () => _pick(context, isStart: false),
        ),
      ),
    ]);
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rt = context.rt;
    return InkWell(
      onTap: onTap,
      borderRadius: RecipeRadius.fieldBR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: rt.paper,
          border: Border.all(color: rt.hair2),
          borderRadius: RecipeRadius.fieldBR,
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 14, color: rt.ink3),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: rt.ink, fontSize: 14)),
        ]),
      ),
    );
  }
}
