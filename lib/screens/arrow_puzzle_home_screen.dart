import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../games/arrow_puzzle/arrow_puzzle_progress.dart';
import '../services/game_reward_ad_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';
import 'arrow_puzzle_play_screen.dart';

/// Arrow Puzzle home (v1.0.27) — follows the user's screenshot:
/// blue Daily Challenge card, "Arrow Puzzle" title, big New Game
/// button, level select grid. Entry point is the Home tab tile in
/// [MainShell] (gated by remote config).
class ArrowPuzzleHomeScreen extends StatefulWidget {
  const ArrowPuzzleHomeScreen({super.key});

  @override
  State<ArrowPuzzleHomeScreen> createState() => _ArrowPuzzleHomeScreenState();
}

class _ArrowPuzzleHomeScreenState extends State<ArrowPuzzleHomeScreen> {
  int _highestUnlocked = 1;
  Map<int, int> _stars = {};
  bool _dailyDone = false;
  bool _loading = true;
  int? _adCoinsBalance;
  bool _watchingAd = false;

  ArrowPuzzleConfig get _cfg =>
      RemoteConfigService.instance.config.arrowPuzzle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final highest = await ArrowPuzzleProgress.highestUnlocked();
    final dailyDone =
        await ArrowPuzzleProgress.isDailyDone(DateTime.now());
    final stars = <int, int>{};
    for (var level = 1; level <= highest; level++) {
      stars[level] = await ArrowPuzzleProgress.starsFor(level);
    }
    int? adBalance;
    try {
      final ad = await SupabaseService.getAdCoins();
      final raw = ad['ad_coins_balance'];
      if (raw is int) adBalance = raw;
    } catch (_) {
      adBalance = null;
    }
    if (!mounted) return;
    setState(() {
      _highestUnlocked = highest;
      _stars = stars;
      _dailyDone = dailyDone;
      _adCoinsBalance = adBalance;
      _loading = false;
    });
  }

  Future<void> _refreshAdCoins() async {
    try {
      final ad = await SupabaseService.getAdCoins();
      final raw = ad['ad_coins_balance'];
      if (mounted && raw is int) setState(() => _adCoinsBalance = raw);
    } catch (_) {
      // Ad Coin display is best-effort; the server enforces the grant.
    }
  }

  /// Watch Ads (flag-gated): a completed rewarded ad earns Ad Coins
  /// via the server claim — the client never credits Ad Coins itself.
  /// Ad Coins are in-game only: they can never become cash or Level
  /// Coins. While the flag is off this button is not rendered at all.
  Future<void> _onWatchAd() async {
    if (_watchingAd) return;
    setState(() => _watchingAd = true);
    final t = AppLocalizations.of(context)!;
    try {
      final grant = await GameRewardAdService.tryGrantAdCoins(
        adsEnabled: _cfg.adsForRewardsEnabled,
      );
      if (grant != AdGrantResult.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.arrowPuzzleAdNotAvailable)),
          );
        }
        return;
      }
      final res = await SupabaseService.claimAdReward(
        idempotencyKey:
            SupabaseService.newIdempotencyKey('ad-reward'),
      );
      final earned = res['ad_coins'];
      if (!mounted) return;
      if (res['already'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.arrowPuzzleAlreadyClaimed)),
        );
      } else if (earned is int) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.arrowPuzzleAdCoinsEarned(earned))),
        );
      }
      unawaited(_refreshAdCoins());
    } on Exception catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('429')
          ? t.arrowPuzzleAdDailyCapReached
          : t.arrowPuzzleAdNotAvailable;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  void _openLevel(int level, {bool dailyChallenge = false}) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ArrowPuzzlePlayScreen(
          level: level,
          dailyChallenge: dailyChallenge,
        ),
      ),
    )
        .then((_) {
      // Progress may have changed (level completed, daily done).
      if (mounted) _load();
    });
  }

  Widget _dailyCard(AppLocalizations t) {
    final now = DateTime.now();
    final dateLabel = DateFormat('MMMM d').format(now);
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF64B5F6), Color(0xFF1E88E5)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_month,
              color: Colors.amber,
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t.arrowPuzzleDailyChallenge.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _dailyDone
                ? null
                : () => _openLevel(0, dailyChallenge: true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            ),
            child: Text(
              _dailyDone ? t.arrowPuzzleDailyDone : t.arrowPuzzlePlay,
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelTile(int level, AppLocalizations t) {
    final locked = level > _highestUnlocked;
    final stars = _stars[level] ?? 0;
    return InkWell(
      onTap: locked ? null : () => _openLevel(level),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: locked
              ? Colors.grey.shade200
              : const Color(0xFFDBEAFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (locked)
              const Icon(Icons.lock, color: Colors.grey)
            else ...[
              Text(
                '$level',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Icon(
                    i < stars ? Icons.star : Icons.star_border,
                    size: 14,
                    color: i < stars ? Colors.amber : Colors.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final shownLevels = _highestUnlocked + 5 > 60 ? 60 : _highestUnlocked + 5;
    // Maze redesign (18 Nov 2026): white background like the
    // reference home screen — the app theme is dark, so text and
    // button colours are set explicitly here.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: Text(t.arrowPuzzleTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _dailyCard(t),
                        const SizedBox(height: 32),
                        Text(
                          t.arrowPuzzleTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2937),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.arrowPuzzleSubtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _openLevel(_highestUnlocked),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E88E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  t.arrowPuzzleNewGame,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                Text(
                                  t.arrowPuzzleLevel(_highestUnlocked),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_cfg.adsForRewardsEnabled) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _watchingAd ? null : _onWatchAd,
                              icon: const Icon(Icons.play_circle_outline),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1E88E5),
                                side: const BorderSide(
                                  color: Color(0xFF1E88E5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              label: Text(
                                t.arrowPuzzleWatchAdGetCoins(
                                  _cfg.adCoinsPerAd,
                                ),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.arrowPuzzleAdCoinsBalance(
                              _adCoinsBalance ?? '—',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                        ],
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: shownLevels,
                          itemBuilder: (context, i) =>
                              _levelTile(i + 1, t),
                        ),
                      ],
                    ),
                  ),
          ),
          const UnityBannerAdWidget(),
        ],
      ),
    );
  }
}
