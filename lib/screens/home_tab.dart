import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../widgets/onboarding_checklist.dart';
import '../widgets/streak_card.dart';
import 'leaderboard_screen.dart';
import 'onboarding_screen.dart';
import 'spin_screen.dart';
import 'streak_screen.dart';

/// Home dashboard: server-side balance + quick actions.
///
/// The balance shown here comes from the `get-balance` Edge Function
/// (SUM of the ledger). Nothing on this screen can change it.
class HomeTab extends StatefulWidget {
  final void Function(int tab) onNavigate;

  const HomeTab({super.key, required this.onNavigate});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<int> _balance;

  @override
  void initState() {
    super.initState();
    _balance = SupabaseService.getBalance();
  }

  /// Rs equivalent of a coin balance (1 coin = Rs 0.01), formatted
  /// without trailing zeros (1000 coins -> "10", 1050 coins -> "10.50").
  String _rsValue(int coins) {
    final rs = coins / 100;
    return rs == rs.roundToDouble()
        ? rs.toInt().toString()
        : rs.toStringAsFixed(2);
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _rewardTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(t.balance,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FutureBuilder<int>(
                    future: _balance,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(t.balanceLoadFailed);
                      }
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      final coins = snapshot.data!;
                      return Column(
                        children: [
                          Text(
                            '$coins',
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium,
                          ),
                          Text(t.coins),
                          const SizedBox(height: 4),
                          // Coins stay primary; the ≈Rs equivalent is
                          // secondary (1 coin = Rs 0.01). Restored per
                          // Jaani, 29 Oct 2026 ("Rs rehny do").
                          Text(
                            t.balanceRsApprox(_rsValue(coins)),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Onboarding checklist for new users (hidden when complete)
          const OnboardingChecklist(),
          const SizedBox(height: 16),
          // Daily streak card (Swagbucks-style retention)
          const StreakCard(),
          const SizedBox(height: 16),
          // Rewards — dedicated screens for each engagement feature
          Text(t.rewardsSection,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _rewardTile(
                icon: Icons.casino,
                label: t.spinTitle,
                onTap: () => _open(const SpinScreen()),
              ),
              _rewardTile(
                icon: Icons.local_fire_department,
                label: t.streakTitle,
                onTap: () => _open(const StreakScreen()),
              ),
              _rewardTile(
                icon: Icons.leaderboard,
                label: t.leaderboardTitle,
                onTap: () => _open(const LeaderboardScreen()),
              ),
              _rewardTile(
                icon: Icons.checklist,
                label: t.tasksTitle,
                onTap: () => _open(const OnboardingScreen()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onNavigate(1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.group_add,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.referTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(t.referSubtitle),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(t.quickActions, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => widget.onNavigate(2),
            child: Text(t.goOffers),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(3),
            child: Text(t.goWallet),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => widget.onNavigate(4),
            child: Text(t.goWithdraw),
          ),
        ],
      ),
    );
  }
}
