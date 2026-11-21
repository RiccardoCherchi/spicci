import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import 'pay_sheet.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Index of the tab shown by the shell, so notification taps can switch to Plan.
class TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final tabProvider = NotifierProvider<TabIndex, int>(TabIndex.new);

const planTab = 1;

/// Runs the monthly saving and refreshes reminders. Safe to call often.
Future<void> refreshPlan(WidgetRef ref) async {
  final repo = ref.read(repoProvider);
  final notifications = ref.read(notificationsProvider);
  final deposits = await repo.runAutoSaving(DateTime.now(), ref.read(savingDayProvider));
  if (deposits.isNotEmpty) {
    ref.read(dataVersionProvider.notifier).bump();
    await notifications.showSaved(deposits);
  }
  await notifications.reschedule(await repo.scheduled());
}

/// Called after a scheduled item is created or changed: asks for notification
/// permission the first time, then reschedules.
Future<void> afterScheduleChange(WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  if (!(prefs.getBool('asked_notifications') ?? false)) {
    await prefs.setBool('asked_notifications', true);
    await ref.read(notificationsProvider).requestPermission();
  }
  ref.read(dataVersionProvider.notifier).bump();
  await refreshPlan(ref);
}

/// Handles the buttons of a due-payment notification.
Future<void> handleNotificationAction(WidgetRef ref, String? action, int scheduledId) async {
  final repo = ref.read(repoProvider);
  final s = (await repo.scheduled()).where((x) => x.id == scheduledId).firstOrNull;
  if (s == null || s.archivedAt != null) return;
  switch (action) {
    case 'snooze':
      final t = DateTime.now().add(const Duration(days: 1));
      await repo.snoozeScheduled(s.id!, DateTime(t.year, t.month, t.day, 9));
    case 'skip':
      await repo.skipScheduled(s);
    default:
      ref.read(tabProvider.notifier).set(planTab);
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) await PaySheet.open(context, s);
      return;
  }
  ref.read(dataVersionProvider.notifier).bump();
  await refreshPlan(ref);
}
