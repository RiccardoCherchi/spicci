import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'data/models.dart';
import 'format.dart';

/// Local notifications for scheduled items. Every action opens the app, so all
/// handling happens in the main isolate with the normal database.
class Notifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _category = 'due';
  static const _savedId = 1;

  /// Called with the action id ('paid', 'snooze', 'skip' or null for a plain tap)
  /// and the scheduled item id.
  void Function(String? action, int scheduledId)? onAction;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } on Object {
      // Unknown zone name: keep UTC rather than failing to start.
    }
    await _plugin.initialize(
      settings: InitializationSettings(
        // Permission is asked later, when the first scheduled item is saved.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(
                  'paid',
                  'plan.paid'.tr(),
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'snooze',
                  'plan.tomorrow'.tr(),
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'skip',
                  'plan.skip'.tr(),
                  options: {DarwinNotificationActionOption.foreground, DarwinNotificationActionOption.destructive},
                ),
              ],
            ),
          ],
        ),
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _handle,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final r = launch!.notificationResponse;
      if (r != null) Future.microtask(() => _handle(r));
    }
  }

  void _handle(NotificationResponse r) {
    final id = int.tryParse(r.payload ?? '');
    if (id != null) onAction?.call(r.actionId, id);
  }

  Future<bool> requestPermission() async =>
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        sound: true,
        badge: true,
      ) ??
      true;

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(categoryIdentifier: _category),
    android: AndroidNotificationDetails('due', 'Due payments', importance: Importance.high),
  );

  /// Replaces all pending reminders with fresh ones for [items].
  Future<void> reschedule(Iterable<Scheduled> items, {DateTime? now}) async {
    await _plugin.cancelAllPendingNotifications();
    final at = now ?? DateTime.now();
    for (final s in items.where((s) => s.archivedAt == null && s.id != null)) {
      final amount = money(s.amountCents);
      final due = DateTime(s.nextDue.year, s.nextDue.month, s.nextDue.day, 9);
      final reminder = due.subtract(Duration(days: s.remindDays));
      final snooze = s.snoozeUntil;
      final slots = <(int, DateTime, String)>[
        if (s.remindDays > 0)
          (0, reminder, 'plan.notify_soon'.tr(namedArgs: {'amount': amount, 'days': '${s.remindDays}'})),
        (1, snooze != null && snooze.isAfter(due) ? snooze : due, 'plan.notify_due'.tr(namedArgs: {'amount': amount})),
      ];
      for (final (slot, time, body) in slots) {
        if (!time.isAfter(at)) continue;
        await _plugin.zonedSchedule(
          id: 1000 + s.id! * 2 + slot,
          scheduledDate: tz.TZDateTime.from(time, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: s.name,
          body: body,
          payload: '${s.id}',
        );
      }
    }
  }

  /// Tells the user what the automatic saving just put aside.
  Future<void> showSaved(List<(Pot, int)> deposits) async {
    if (deposits.isEmpty) return;
    final total = deposits.fold(0, (sum, d) => sum + d.$2);
    await _plugin.show(
      id: _savedId,
      title: 'plan.saved_title'.tr(namedArgs: {'amount': money(total)}),
      body: deposits.map((d) => '${d.$1.name} +${money(d.$2)}').join(' · '),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails('saved', 'Piggy banks'),
      ),
    );
  }
}
