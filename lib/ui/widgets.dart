import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../theme/theme.dart';
import 'solar.dart';

/// Tinted rounded square with a duotone glyph.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 40});

  /// A category icon name from [categoryIcons].
  final String icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.32)),
    alignment: Alignment.center,
    child: SolarIcon.category(icon, color: color, size: size * 0.55),
  );
}

/// An amount whose cents are drawn smaller and dimmer.
class MoneyText extends StatelessWidget {
  const MoneyText(this.text, {super.key, required this.style, this.centsColor});

  /// Already formatted, sign included.
  final String text;
  final TextStyle style;
  final Color? centsColor;

  @override
  Widget build(BuildContext context) {
    final (whole, cents, tail) = splitCents(text);
    final small = style.copyWith(
      fontSize: (style.fontSize ?? 14) * 0.62,
      color: centsColor ?? style.color?.withValues(alpha: 0.6),
      letterSpacing: 0,
    );
    return Text.rich(
      TextSpan(
        style: style.copyWith(fontFeatures: tabular),
        children: [
          TextSpan(text: whole),
          TextSpan(text: cents, style: small),
          TextSpan(text: tail, style: small),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// Rounded pill used for chips and small actions.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.leading, this.trailing, this.onTap, this.color});

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: color ?? t.card,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              ?leading,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing active accounts; sized to its content.
Future<Account?> pickAccount(BuildContext context, List<Account> accounts, {int? selectedId, int? excludeId}) {
  final options = accounts.where((a) => a.deletedAt == null && a.active && a.id != excludeId).toList();
  var done = false;
  return showModalBottomSheet<Account>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          for (final a in options)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: IconTile(icon: a.icon, color: accountColor(a.color)),
              title: Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: a.id == selectedId ? SolarIcon.ui(Ui.checkCircle, color: sheet.tokens.accentInk) : null,
              onTap: () {
                // A fast double tap must not pop the page under the sheet.
                if (done) return;
                done = true;
                Navigator.pop(sheet, a);
              },
            ),
        ],
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(color: context.tokens.muted, fontSize: 13, fontFeatures: tabular),
          ),
      ],
    ),
  );
}

String txTypeKey(TxType t) => switch (t) {
  TxType.expense => 'add.expense',
  TxType.income => 'add.income',
  TxType.transfer => 'add.transfer',
};

/// Bottom sheet asking to confirm a destructive action; [action] defaults to Delete.
Future<bool> confirm(BuildContext context, String title, String body, {String? action}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gap, 0, gap, gap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(body, style: TextStyle(color: c.tokens.muted, height: 1.4)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.tokens.expense, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true),
                child: Text(action ?? 'add.delete'.tr()),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text('add.cancel'.tr())),
            ],
          ),
        ),
      ),
    ) ??
    false;

/// Line chart touch with a tooltip; [label] gives one row per touched spot, [first] marks the top row.
LineTouchData lineTouch(BuildContext context, String Function(LineBarSpot spot, bool first) label) {
  final t = context.tokens;
  return LineTouchData(
    touchTooltipData: LineTouchTooltipData(
      getTooltipColor: (_) => t.card2,
      tooltipBorderRadius: BorderRadius.circular(10),
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      maxContentWidth: 180,
      getTooltipItems: (spots) => [
        for (final (i, s) in spots.indexed)
          LineTooltipItem(
            label(s, i == 0),
            TextStyle(color: t.ink, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular),
          ),
      ],
    ),
  );
}
