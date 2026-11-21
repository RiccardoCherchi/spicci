import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'add_page.dart';
import 'analysis_page.dart';
import 'home_page.dart';
import 'plan_actions.dart';
import 'plan_page.dart';
import 'settings_page.dart';
import 'solar.dart';

class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: tab, children: const [HomePage(), PlanPage(), AnalysisPage(), SettingsPage()]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Center(
          heightFactor: 1,
          child: _NavPill(tab: tab, onTab: ref.read(tabProvider.notifier).set),
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.tab, required this.onTab});
  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget item(int i, Ui icon, String label) => IconButton(
      tooltip: label.tr(),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTab(i);
      },
      icon: SolarIcon.ui(icon, color: tab == i ? t.ink : t.muted, size: 26),
      padding: const EdgeInsets.all(14),
    );

    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: t.card2.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: t.line.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              item(0, Ui.home2, 'nav.home'),
              item(planTab, Ui.calendar, 'nav.plan'),
              item(2, Ui.graphUp, 'nav.analysis'),
              item(3, Ui.settings, 'nav.settings'),
            ],
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        pill,
        Semantics(
          button: true,
          label: 'nav.add'.tr(),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              AddPage.open(context);
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.add_rounded, color: t.onAccent, size: 34),
            ),
          ),
        ),
      ],
    );
  }
}
