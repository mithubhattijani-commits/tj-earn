import 'package:flutter/material.dart';

import '../services/startup_bundle_service.dart';
import 'package:tj_earn/l10n/app_localizations.dart';


/// New-user onboarding checklist (Roz Dhan-style welcome tasks).
///
/// Shows 4 tasks: profile, checkin, quiz, referral.
/// Completing all earns the onboarding bonus (default 100 coins).
/// Hidden once all tasks are complete.
class OnboardingChecklist extends StatefulWidget {
  const OnboardingChecklist({super.key});

  @override
  State<OnboardingChecklist> createState() => _OnboardingChecklistState();
}

class _OnboardingChecklistState extends State<OnboardingChecklist> {
  List<String> _completed = [];
  bool _settled = false;
  bool _allDone = false;

  @override
  void initState() {
    super.initState();
    // Cache-first (Jaani, 2 Nov 2026 — PERMANENT hang fix): the last-known
    // checklist renders INSTANTLY from local cache; a background refresh
    // updates it silently. initState never awaits the network.
    _completed = StartupBundleService.onboardingCompleted;
    _allDone = _completed.length >= 4;
    _settled = StartupBundleService.hasCache;
    StartupBundleService.refreshInBackground();
    StartupBundleService.refreshDone.addListener(_onRefresh);
  }

  /// Re-read the onboarding slice on every completed refresh attempt.
  void _onRefresh() {
    if (!mounted) return;
    final completed = StartupBundleService.onboardingCompleted;
    setState(() {
      _completed = completed;
      _settled = true;
      _allDone = completed.length >= 4;
    });
  }

  @override
  void dispose() {
    StartupBundleService.refreshDone.removeListener(_onRefresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (!_settled || _allDone) return const SizedBox.shrink();

    final tasks = [
      ('profile', t.onboardingProfile, Icons.person),
      ('checkin', t.onboardingCheckin, Icons.check_circle),
      ('quiz', t.onboardingQuiz, Icons.quiz),
      ('referral', t.onboardingReferral, Icons.share),
    ];

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.onboardingTitle('100'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              t.onboardingSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              t.onboardingProgress(
                _completed.length.toString(),
                tasks.length.toString(),
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            // Animated progress bar toward the onboarding bonus
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _completed.length / tasks.length,
                minHeight: 8,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            ...tasks.map((task) {
              final isDone = _completed.contains(task.$1);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isDone ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Icon(task.$3, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Text(task.$2)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
