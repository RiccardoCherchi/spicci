import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme/theme.dart';
import 'solar.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Bottom sheet date picker: one tap picks a day and closes. Recent days sit in
/// a strip on top; the month grid below marks days that already have entries.
/// The time of [initial] is kept.
Future<DateTime?> pickDay(BuildContext context, {required DateTime initial, Set<DateTime> marked = const {}}) async {
  final picked = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DateSheet(selected: _day(initial), marked: marked),
  );
  return picked == null ? null : DateTime(picked.year, picked.month, picked.day, initial.hour, initial.minute);
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({required this.selected, required this.marked});
  final DateTime selected;
  final Set<DateTime> marked;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  var _done = false;

  void _pick(DateTime d) {
    // A fast double tap must not pop the page under the sheet.
    if (_done) return;
    _done = true;
    HapticFeedback.selectionClick();
    Navigator.pop(context, d);
  }

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final today = _day(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(gap, 0, gap, gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 14,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final d = today.subtract(Duration(days: i));
                  final label = switch (i) {
                    0 => 'day.today'.tr(),
                    1 => 'day.yesterday'.tr(),
                    _ => DateFormat.E(lang).format(d),
                  };
                  return _QuickDay(
                    top: label,
                    bottom: '${d.day}',
                    selected: d == widget.selected,
                    onTap: () => _pick(d),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    toBeginningOfSentenceCase(DateFormat.yMMMM(lang).format(_month)),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                _Arrow(icon: Ui.altArrowLeft, onTap: () => _shift(-1)),
                const SizedBox(width: 6),
                _Arrow(icon: Ui.altArrowRight, onTap: () => _shift(1)),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 200) _shift(v < 0 ? 1 : -1);
              },
              child: _MonthGrid(
                month: _month,
                selected: widget.selected,
                today: today,
                marked: widget.marked,
                firstWeekday: firstWeekday,
                weekdayNames: [for (var i = 0; i < 7; i++) DateFormat.E(lang).format(DateTime(2024, 1, 7 + i))],
                onPick: _pick,
                mutedColor: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickDay extends StatelessWidget {
  const _QuickDay({required this.top, required this.bottom, required this.selected, required this.onTap});
  final String top;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.onAccent : t.ink;
    return Material(
      color: selected ? t.accent : t.card2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                top,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7)),
              ),
              Text(
                bottom,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final Ui icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card2,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(9), child: SolarIcon.ui(icon, size: 18)),
    ),
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.marked,
    required this.firstWeekday,
    required this.weekdayNames,
    required this.onPick,
    required this.mutedColor,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Set<DateTime> marked;

  /// 0 = Sunday, 1 = Monday.
  final int firstWeekday;

  /// Short names starting from Sunday.
  final List<String> weekdayNames;
  final ValueChanged<DateTime> onPick;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = (DateTime(month.year, month.month).weekday % 7 - firstWeekday + 7) % 7;
    final cells = <Widget>[
      for (var i = 0; i < 7; i++)
        Center(
          child: Text(
            weekdayNames[(firstWeekday + i) % 7].characters.take(2).toString(),
            style: TextStyle(color: mutedColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _cell(t, DateTime(month.year, month.month, d)),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Widget _cell(Tokens t, DateTime d) {
    final isSelected = d == selected;
    final isToday = d == today;
    final future = d.isAfter(today);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onPick(d),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? t.accent : null,
            border: isToday && !isSelected ? Border.all(color: t.accentInk, width: 1.5) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? t.onAccent : (future ? t.muted : t.ink),
                ),
              ),
              if (marked.contains(d) && !isSelected)
                Positioned(
                  bottom: 5,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: t.muted, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
