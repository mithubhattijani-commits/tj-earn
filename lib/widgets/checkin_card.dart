import 'package:flutter/material.dart';

import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/startup_bundle_service.dart';
import '../services/checkin_reminder_service.dart';
import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';
import '../theme.dart';

/// Daily check-in card with streak progression (Jaani, 3 Nov 2026).
///
/// Reward: Day 1 = 10 coins, Day 2 = 15, Day 3 = 20, ... (+5 per
/// consecutive day, capped at 100/day). A missed day resets to Day 1.
/// One check-in per PKT day.
///
/// Cache-first like StreakCard: renders instantly from the startup bundle,
/// refreshes silently in the background. No infinite spinners, no UI-thread
/// blocking — every network call has a hard timeout via SupabaseService.
class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key});

  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  Map<String, dynamic>? _streak;
  bool _settled = false;
  bool _claiming = false;
  String? _message;
  int? _justEarned;

  @override
  void initState() {
    super.initState();
    _streak = StartupBundleService.streak;
    _settled = StartupBundleService.hasCache;
    StartupBundleService.refreshInBackground();
    StartupBundleService.refreshDone.addListener(_onRefresh);
  }

  void _onRefresh() {
    if (!mounted) return;
    final s = StartupBundleService.streak;
    final changed = (s == null) != (_streak == null) ||
        s?['current_streak'] != _streak?['current_streak'] ||
        s?['last_checkin_date'] != _streak?['last_checkin_date'] ||
        !_settled;
    if (changed) {
      setState(() {
        _streak = s;
        _settled = true;
      });
      // Keep the 9 PM reminder text in sync with the fresh streak data.
      // ignore: unawaited_futures
      CheckinReminderService.instance.scheduleIfNeeded();
    }
  }

  @override
  void dispose() {
    StartupBundleService.refreshDone.removeListener(_onRefresh);
    super.dispose();
  }

  /// PKT calendar day key (matches the server's day boundary).
  String _pktToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  int _coinsForDay(int day) {
    final coins = 10 + (day - 1) * 5;
    return coins > 100 ? 100 : coins;
  }

  Future<void> _claim() async {
    if (_claiming) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _claiming = true;
      _message = null;
      _justEarned = null;
    });
    try {
      final result = await SupabaseService.claimCheckin();
      if (!mounted) return;
      final already = result['already_claimed'] == true;
      final coins = (result['coins'] as int?) ?? 0;
      final day = (result['streak_day'] as int?) ?? 1;
      setState(() {
        _claiming = false;
        if (already) {
          _message = t?.checkinAlreadyDone;
        } else {
          _justEarned = coins;
          _message = t?.checkinEarned(coins.toString(), day.toString());
        }
      });
      // Refresh the cached streak so the card shows the new state.
      StartupBundleService.refreshInBackground();
      if (!already) {
        // Checked in — cancel today's 9 PM reminder (it will be
        // rescheduled tomorrow on app start if not checked in).
        // ignore: unawaited_futures
        CheckinReminderService.instance.cancel();
      }
      if (!already && coins > 0) {
        // ignore: unawaited_futures
        UnityAdsService.showClaimInterstitial();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_settled) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final current = _streak?['current_streak'] as int? ?? 0;
    final String? lastCheckin = _streak?['last_checkin_date'] as String?;
    final bool claimedToday = lastCheckin == _pktToday();
    // If never checked in, today pays Day 1 (10 coins).
    final int todayDay = claimedToday ? current : (current > 0 ? current + 1 : 1);
    final int todayCoins = _coinsForDay(todayDay);
    final int tomorrowCoins = _coinsForDay(todayDay + 1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 32,
                  color: current > 0 ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t?.checkinTitle ?? 'Daily Check-in',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (current > 0)
                        Text(
                          t?.checkinStreak(current.toString()) ??
                              '$current day streak',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                        ),
                    ],
                  ),
                ),
                if (!claimedToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: TjEarnTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: TjEarnTheme.gold),
                    ),
                    child: Text(
                      '+$todayCoins',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: TjEarnTheme.gold,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              claimedToday
                  ? (t?.checkinComeBack(tomorrowCoins.toString()) ??
                      'Come back tomorrow for +$tomorrowCoins coins')
                  : (t?.checkinTodayPays(
                          todayDay.toString(), todayCoins.toString()) ??
                      'Day $todayDay: check in now for +$todayCoins coins'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (claimedToday || _claiming) ? null : _claim,
                icon: _claiming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(claimedToday
                    ? (t?.checkinDone ?? 'Checked In ✓')
                    : (t?.checkinButton ?? 'Check In')),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: _justEarned != null
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                  fontWeight: _justEarned != null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
