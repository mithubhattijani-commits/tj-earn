import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../widgets/streak_card.dart';

/// Dedicated Daily Streak screen.
///
/// Wraps the [StreakCard] widget (current streak, milestone progress
/// 7/14/21/30 days, milestone bonus claims via the `claim-streak`
/// Edge Function) in a full page reachable from Home.
class StreakScreen extends StatelessWidget {
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.streakTitle)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: StreakCard(),
      ),
    );
  }
}
