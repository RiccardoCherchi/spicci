import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'solar.dart';
import 'widgets.dart';

/// Grid of every category icon, tinted with [color].
Future<String?> pickIcon(BuildContext context, {required String current, required Color color}) {
  final names = categoryIcons.keys.toList()..sort();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.6,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(gap, 0, gap, gap),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 64,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: names.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.pop(sheet, names[i]),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: names[i] == current ? sheet.tokens.accentInk : Colors.transparent, width: 2),
              ),
              padding: const EdgeInsets.all(2),
              child: IconTile(icon: names[i], color: color, size: 52),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Wrapping row of colour dots.
class ColorRow extends StatelessWidget {
  const ColorRow({super.key, required this.colors, required this.selected, required this.onChanged});
  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final (i, c) in colors.indexed)
        GestureDetector(
          onTap: () => onChanged(i),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: i == selected ? context.tokens.ink : Colors.transparent, width: 2.5),
            ),
          ),
        ),
    ],
  );
}

/// One option of [pickOption].
class Option<T> {
  const Option(this.value, this.label, {this.leading});
  final T value;
  final String label;
  final Widget? leading;
}

/// Single-choice list in a bottom sheet, sized to its content.
Future<Option<T>?> pickOption<T>(BuildContext context, List<Option<T>> options, {T? selected}) =>
    showModalBottomSheet<Option<T>>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final o in options)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: o.leading,
                  title: Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: o.value == selected ? SolarIcon.ui(Ui.checkCircle, color: sheet.tokens.accentInk) : null,
                  onTap: () => Navigator.pop(sheet, o),
                ),
            ],
          ),
        ),
      ),
    );

/// Labelled block inside editor sheets.
class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Text(
        label,
        style: TextStyle(color: context.tokens.muted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child,
    ],
  );
}

/// Plain page scaffold used by the management screens.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.body, this.actions = const []});
  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: () => Navigator.pop(context), icon: SolarIcon.ui(Ui.altArrowLeft)),
      title: Text(title),
      centerTitle: true,
      actions: actions,
    ),
    body: body,
  );
}
