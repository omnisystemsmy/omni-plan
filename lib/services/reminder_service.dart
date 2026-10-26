import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart' show PlanTask;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Task reminders as local device notifications. Nothing here needs a
/// server: the phone shows them even when the app is closed.
///
/// Each sync replaces every pending reminder with the current set, so
/// editing a task many times never leaves duplicates behind, and a deleted,
/// completed or rescheduled task never fires an old reminder. Times are
/// scheduled as absolute instants (UTC), computed from the person's local
/// due time, so no time-zone database lookup is needed.
class ReminderService extends ChangeNotifier {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  /// Android keeps a limited number of alarms per app; the nearest ones are
  /// scheduled and the rest follow at the next sync.
  static const int maxScheduled = 60;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController.broadcast();
  bool _ready = false;
  bool _supported = true;
  bool? _permissionGranted;
  Timer? _debounce;

  /// Task ids from reminders the person tapped.
  Stream<String> get taps => _taps.stream;

  /// Null until the system has been asked.
  bool? get permissionGranted => _permissionGranted;
  bool get supported => _supported;
  int scheduledCount = 0;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'omni_plan_reminders',
      'Task reminders',
      channelDescription: 'Reminders for tasks you set a reminder on',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready) return;
    if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      _supported = false;
      return;
    }
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final payload = r.payload;
          if (payload != null && payload.startsWith('task:')) {
            _taps.add(payload.substring(5));
          }
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.startsWith('task:')) {
        // Delivered once the shell is listening.
        Future<void>.delayed(const Duration(seconds: 1), () => _taps.add(payload.substring(5)));
      }
      _ready = true;
    } catch (e) {
      debugPrint('[ReminderService] not available: $e');
      _supported = false;
    }
  }

  /// Asks the system for permission to show notifications.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      bool? granted;
      if (defaultTargetPlatform == TargetPlatform.android) {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      _permissionGranted = granted ?? true;
    } catch (_) {
      _permissionGranted = false;
    }
    notifyListeners();
    return _permissionGranted!;
  }

  /// Schedules after changes settle, so a burst of edits causes one sync.
  void scheduleSync(PlanStore store) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => sync(store));
  }

  /// The reminders that should be pending now, nearest first.
  static List<(PlanTask, DateTime)> upcoming(PlanStore store, DateTime now) {
    final list = <(PlanTask, DateTime)>[
      for (final t in store.tasks)
        if (!t.isDone && t.reminderAt != null && t.reminderAt!.isAfter(now))
          (t, t.reminderAt!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return list.take(maxScheduled).toList();
  }

  Future<void> sync(PlanStore store) async {
    if (!_ready || !store.isOpen) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      scheduledCount = 0;
      if (!store.prefs.notifyReminders) {
        notifyListeners();
        return;
      }
      final items = upcoming(store, DateTime.now());
      if (items.isEmpty) {
        notifyListeners();
        return;
      }
      if (_permissionGranted == null) await requestPermission();
      if (_permissionGranted == false) return;
      for (final (task, at) in items) {
        final project = store.project(task.projectId);
        await _plugin.zonedSchedule(
          _idFor(task.id),
          task.title,
          [
            if (task.dueMinutes != null) 'Due at ${_hhmm(task.dueMinutes!)}' else 'Due today',
            if (project != null) project.name,
          ].join(' · '),
          tz.TZDateTime.from(at.toUtc(), tz.UTC),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'task:${task.id}',
        );
        scheduledCount++;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ReminderService] sync failed: $e');
    }
  }

  static String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// A stable 31-bit id per task.
  static int _idFor(String taskId) {
    var h = 0;
    for (final c in taskId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      scheduledCount = 0;
      notifyListeners();
    } catch (_) {}
  }
}
