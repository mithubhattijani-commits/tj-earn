import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// Weekly leaderboard: top earners by coins earned in the last 7 days.
///
/// Anonymized display (User #XXXX). Shows the caller's own rank.
/// Drives competition and retention via social proof.
class LeaderboardWidget extends StatefulWidget {
  const LeaderboardWidget({super.key});

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget> {
  List<dynamic> _entries = [];
  int _myRank = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.getLeaderboard();
      if (mounted) {
        setState(() {
          _entries = (data['leaderboard'] as List?) ?? [];
          _myRank = (data['my_rank'] as int?) ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.leaderboard,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.leaderboardTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        t.leaderboardSubtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(t.leaderboardEmpty)),
              )
            else
              ..._entries.take(10).map((entry) {
                final e = entry as Map<String, dynamic>;
                final isMe = e['is_me'] as bool? ?? false;
                final rank = e['rank'] as int? ?? 0;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                        : (rank <= 3
                            ? Colors.amber.shade50
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: rank == 1
                                ? Colors.amber.shade700
                                : rank == 2
                                    ? Colors.grey.shade600
                                    : rank == 3
                                        ? Colors.brown.shade600
                                        : null,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          isMe
                              ? t.leaderboardYou
                              : (e['display'] as String? ?? 'User'),
                          style: TextStyle(
                            fontWeight:
                                isMe ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      Text(
                        '${e['coins']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
            if (_myRank > 0) ...[
              const Divider(),
              Text(
                t.leaderboardYourRank(_myRank.toString()),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
