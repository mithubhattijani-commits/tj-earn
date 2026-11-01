import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';

/// New-user onboarding checklist (Roz Dhan-style welcome tasks).
///
/// Shows 5 tasks: profile, checkin, quiz, spin, referral.
/// Completing all earns the onboarding bonus (default 100 coins).
/// Hidden once all tasks are complete.
class OnboardingChecklist extends StatefulWidget {
  const OnboardingChecklist({super.key});

  @override
  State<OnboardingChecklist> createState() => _OnboardingChecklistState();
}

class _OnboardingChecklistState extends State<OnboardingChecklist> {
  List<String> _completed = [];
  bool _loading = true;
  bool _allDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final completed = await SupabaseService.getOnboardingProgress();
      if (mounted) {
        setState(() {
          _completed = completed;
          _loading = false;
          _allDone = completed.length >= 5;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_loading || _allDone) return const SizedBox.shrink();

    final tasks = [
      ('profile', t.onboardingProfile, Icons.person),
      ('checkin', t.onboardingCheckin, Icons.check_circle),
      ('quiz', t.onboardingQuiz, Icons.quiz),
      ('spin', t.onboardingSpin, Icons.casino),
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
