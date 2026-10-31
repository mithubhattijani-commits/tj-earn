import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../widgets/onboarding_checklist.dart';

/// Dedicated My Tasks screen.
///
/// Wraps the [OnboardingChecklist] widget (5 welcome tasks, 100-coin
/// bonus on completion via the `claim-onboarding` Edge Function) in a
/// full page reachable from Home.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.tasksTitle)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: OnboardingChecklist(),
      ),
    );
  }
}
