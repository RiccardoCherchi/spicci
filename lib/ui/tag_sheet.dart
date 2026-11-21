import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'solar.dart';
import 'widgets.dart';

/// Lets the user toggle known tags or type new ones. Returns null when dismissed.
Future<List<String>?> pickTags(BuildContext context, {required List<String> selected, required List<String> known}) =>
    showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagSheet(selected: selected, known: known),
    );

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.selected, required this.known});
  final List<String> selected;
  final List<String> known;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  late final _selected = [...widget.selected];
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final name = _input.text.trim().replaceAll('#', '');
    if (name.isEmpty) return;
    setState(() {
      if (!_selected.contains(name)) _selected.add(name);
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final query = _input.text.trim().toLowerCase();
    final options = {...widget.known, ..._selected}.where((n) => query.isEmpty || n.toLowerCase().contains(query));
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 0, gap, MediaQuery.viewInsetsOf(context).bottom + gap),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text('tags.title'.tr(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            TextField(
              controller: _input,
              autofocus: widget.known.isEmpty,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: 'tags.hint'.tr(),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SolarIcon.ui(Ui.hashtag, size: 20, color: t.muted),
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _add,
                        icon: SolarIcon.ui(Ui.addCircle, color: t.accentInk),
                      ),
              ),
            ),
            if (options.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in options)
                        Pill(
                          label: '#$name',
                          color: _selected.contains(name) ? t.accent.withValues(alpha: 0.18) : t.card2,
                          trailing: _selected.contains(name)
                              ? SolarIcon.ui(Ui.checkCircle, size: 16, color: t.accentInk)
                              : null,
                          onTap: () =>
                              setState(() => _selected.contains(name) ? _selected.remove(name) : _selected.add(name)),
                        ),
                    ],
                  ),
                ),
              ),
            FilledButton(
              onPressed: () {
                _add();
                Navigator.pop(context, _selected);
              },
              child: Text('tags.done'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
