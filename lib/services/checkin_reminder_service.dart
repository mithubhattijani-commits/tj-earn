import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'startup_bundle_service.dart';

/// Daily check-in reminder notification (Jaani, 3 Nov 2026).
///
/// Fires a local notification at 9 PM PKT every day reminding the user to
/// claim their daily check-in — but ONLY if they haven't checked in yet
/// that day. Uses flutter_local_notifications (no server needed).
///
/// Flow:
/// - [init] initializes the plugin + Asia/Karachi timezone, requests
///   notification permission on first launch (denial is fine — we just
///   don't schedule), then schedules based on today's check-in state.
/// - [scheduleIfNeeded] reads the cached streak; if the user already
///   checked in today (PKT), any pending reminder is cancelled; otherwise
///   a daily 9 PM PKT notification is (re)scheduled with the Day-N / coins
///   text.
/// - [cancel] removes the pending reminder (called after a successful
///   check-in claim).
///
/// Best-effort throughout: no throw, no UI-thread blocking, every step
/// guarded. A reminder failure must never break the app.
class CheckinReminderService {
  CheckinReminderService._();
  static final CheckinReminderService instance = CheckinReminderService._();

  static const int _notificationId = 1001;
  static const String _channelId = 'checkin_reminder';
  static const String _channelName = 'Daily Check-in Reminder';
  static const String _permAskedKey = 'checkin_reminder_perm_asked_v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initializes the plugin and timezone data. Safe to call multiple times.
  /// Never throws; failures are swallowed (reminder is best-effort).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(settings);

      // Request permission on first launch only (Android 13+).
      // Denial is fine — we simply won't schedule.
      try {
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 5));
        final asked = prefs.getBool(_permAskedKey) ?? false;
        if (!asked) {
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission()
              .timeout(const Duration(seconds: 10));
          await prefs.setBool(_permAskedKey, true);
        }
      } catch (_) {
        // Permission flow is best-effort; continue to scheduling.
      }

      await scheduleIfNeeded();
    } catch (_) {
      // Best-effort: never crash the app over a reminder.
    }
  }

  /// PKT calendar day key (matches the server's day boundary).
  String _pktDayKey(DateTime utc) {
    final pkt = utc.add(const Duration(hours: 5));
    return '${pkt.year}-${pkt.month.toString().padLeft(2, '0')}-${pkt.day.toString().padLeft(2, '0')}';
  }

  String _pktToday() => _pktDayKey(DateTime.now().toUtc());

  String _pktYesterday() =>
      _pktDayKey(DateTime.now().toUtc().subtract(const Duration(days: 1)));

  int _coinsForDay(int day) {
    final coins = 10 + (day - 1) * 5;
    return coins > 100 ? 100 : coins;
  }

  /// Schedules the daily 9 PM PKT reminder if the user has NOT checked in
  /// today; cancels any pending reminder if they already have.
  ///
  /// The Day-N / coins text is computed from the cached streak: if the
  /// last check-in was yesterday (streak alive), the next claim continues
  /// the streak; otherwise the streak lapsed and the next claim is Day 1.
  Future<void> scheduleIfNeeded() async {
    if (!_initialized) return;
    try {
      final streak = StartupBundleService.streak;
      final String? lastCheckin = streak?['last_checkin_date'] as String?;
      final bool claimedToday = lastCheckin == _pktToday();
      if (claimedToday) {
        await cancel();
        return;
      }
      final current = streak?['current_streak'] as int? ?? 0;
      final bool streakAlive =
          lastCheckin == _pktYesterday() && current > 0;
      final int nextDay = streakAlive ? current + 1 : 1;
      final int coins = _coinsForDay(nextDay);

      // ignore: lines_longer_than_80_chars
      final body =
          '🔥 Aaj ka check-in miss na karo! Day $nextDay par $coins coins tumhara intezar kar rahe hain. Abhi claim karo!';

      await _plugin
          .zonedSchedule(
            _notificationId,
            'Daily Check-in ⏰',
            body,
            _next9pm(),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                _channelName,
                channelDescription:
                    'Reminds you to claim your daily check-in coins',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Returns the next 9 PM in Asia/Karachi time.
  tz.TZDateTime _next9pm() {
    final karachi = tz.getLocation('Asia/Karachi');
    final now = tz.TZDateTime.now(karachi);
    var scheduled =
        tz.TZDateTime(karachi, now.year, now.month, now.day, 21);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Cancels the pending check-in reminder.
  Future<void> cancel() async {
    try {
      await _plugin.cancel(_notificationId).timeout(
            const Duration(seconds: 5),
          );
    } catch (_) {}
  }
}
