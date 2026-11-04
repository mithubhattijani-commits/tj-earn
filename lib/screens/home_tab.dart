import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/remote_config_service.dart';
import '../services/startup_bundle_service.dart';
import '../theme.dart';
import '../widgets/adsterra_app_banner.dart';
import '../widgets/onboarding_checklist.dart';
import '../widgets/checkin_card.dart';
import 'leaderboard_screen.dart';
import 'onboarding_screen.dart';
import 'streak_screen.dart';
import 'watch_ad_screen.dart';

/// Home dashboard: server-side balance + quick actions.
///
/// The balance shown here comes from the `get-balance` Edge Function
/// (SUM of the ledger). Nothing on this screen can change it.
/// Server-driven sponsored ad card (Jaani, 2 Nov 2026).
///
/// Visible only when the Remote Config enables it with a non-empty title
/// and action URL. Tap opens the action URL in the external browser;
/// the tap never auto-fires and the card hides gracefully if the image
/// fails to load. Renders nothing (zero height) when disabled.
class SponsoredAdCard extends StatelessWidget {
  const SponsoredAdCard({super.key});

  Future<void> _openAd(String actionUrl) async {
    try {
      final Uri uri = Uri.parse(actionUrl.trim());
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Ad taps must never break the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (BuildContext context, RemoteConfig cfg, _) {
        final SponsoredAdConfig ad = cfg.sponsoredAd;
        if (!ad.show) {
          return const SizedBox.shrink();
        }
        final String imageUrl = ad.imageUrl.trim();
        return Column(
          children: [
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openAd(ad.actionUrl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.network(
                          imageUrl,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.campaign,
                            color: TjEarnTheme.gold,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              ad.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: TjEarnTheme.gold),
                            ),
                          ),
                          const Icon(Icons.open_in_new, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class HomeTab extends StatefulWidget {
  final void Function(int tab) onNavigate;

  const HomeTab({super.key, required this.onNavigate});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  int? _coins;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // Cache-first (Jaani, 2 Nov 2026 — PERMANENT hang fix): the last-known
    // balance renders INSTANTLY from local cache; a single background
    // refresh updates it silently. initState never awaits the network.
    _coins = StartupBundleService.balanceCoins;
    StartupBundleService.refreshInBackground();
    StartupBundleService.refreshDone.addListener(_onRefresh);
  }

  /// Re-read the sync getters on every completed refresh attempt
  /// (success or failure).
  void _onRefresh() {
    if (!mounted) return;
    final coins = StartupBundleService.balanceCoins;
    if (coins != _coins || (coins == null) != _loadFailed) {
      setState(() {
        _coins = coins;
        // No usable balance after a completed attempt = failure state.
        _loadFailed = coins == null;
      });
    }
  }

  @override
  void dispose() {
    StartupBundleService.refreshDone.removeListener(_onRefresh);
    super.dispose();
  }

  /// Balance card body: cached coins render instantly; spinner only on
  /// the very first run with no cache; error + retry when the server is
  /// unreachable.
  Widget _buildBalanceBody() {
    final t = AppLocalizations.of(context)!;
    if (_loadFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.balanceLoadFailed),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => StartupBundleService.refreshNow(),
            child: Text(t.retry),
          ),
        ],
      );
    }
    final coins = _coins;
    if (coins == null) {
      // First-ever run, cache empty, refresh still in flight.
      return const CircularProgressIndicator();
    }
    return Column(
      children: [
        Text(
          '$coins',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: TjEarnTheme.gold,
                fontWeight: FontWeight.bold,
              ),
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
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [TjEarnTheme.navyTop, TjEarnTheme.navyBottom],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: TjEarnTheme.gold.withValues(alpha: 0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(t.balance,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildBalanceBody(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Onboarding checklist for new users (hidden when complete)
          const OnboardingChecklist(),
          const SizedBox(height: 16),
          // Daily check-in card (Jaani, 3 Nov 2026: +5/day streak progression)
          const CheckInCard(),
          const SizedBox(height: 16),
          // Server-driven sponsored ad (Remote Config). Zero height when
          // the server disables it — no layout shift, no placeholder.
          const SponsoredAdCard(),
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
              _rewardTile(
                icon: Icons.play_circle_outline,
                label: t.watchAdTile,
                onTap: () => _open(const WatchAdScreen()),
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
          // Dual-ad system (Jaani, 2 Nov 2026): Adsterra banner from the
          // website loads on every home visit — real impression alongside
          // the Unity ads shown in-app.
          const SizedBox(height: 16),
          const Center(child: AdsterraAppBanner()),
        ],
      ),
    );
  }
}
