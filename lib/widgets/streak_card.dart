import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Daily streak display card.
///
/// Shows the user's current check-in streak with a flame icon,
/// progress to the next milestone (7/14/21/30 days), and milestone
/// bonuses. Tapping claims the daily streak (after check-in).
class StreakCard extends StatefulWidget {
  const StreakCard({super.key});

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  Map<String, dynamic>? _streak;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final streak = await SupabaseService.getStreak();
      if (mounted) {
        setState(() {
          _streak = streak;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim() async {
    final t = AppLocalizations.of(context)!;
    try {
      final result = await SupabaseService.claimStreak();
      if (!mounted) return;
      final bonus = result['bonus_coins'] as int? ?? 0;
      setState(() {
        _message = bonus > 0
            ? t.streakMilestone(bonus.toString())
            : t.streakKeepGoing;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final current = _streak?['current_streak'] as int? ?? 0;
    final nextMilestone = [7, 14, 21, 30].firstWhere(
      (m) => m > current,
      orElse: () => 30,
    );
    final progress = current / nextMilestone;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _claim,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 32,
                    color: current > 0 ? Colors.orange : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.streakTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          t.streakDays(current.toString()),
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.orange.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                t.streakNext(nextMilestone.toString()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
