import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../widgets/leaderboard.dart';

/// Dedicated Weekly Leaderboard screen.
///
/// Wraps the [LeaderboardWidget] (top 20 earners, anonymized, via the
/// `get-leaderboard` Edge Function) in a full page reachable from Home.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.leaderboardTitle)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: LeaderboardWidget(),
      ),
    );
  }
}
