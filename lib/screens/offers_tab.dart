import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';
import '../widgets/leaderboard.dart';

/// Rewards & offers page.
///
/// Unity rewarded video lives here: the user taps "Watch Ad", watches the
/// full video, and earns coins. Coins are credited server-side by the
/// `claim-unity-reward` Edge Function — the app never writes to the ledger.
///
/// Rewards are coins (virtual currency), never cash — per Unity policy.
class OffersTab extends StatefulWidget {
  const OffersTab({super.key});

  @override
  State<OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends State<OffersTab> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  Future<void> _watchAd() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    final t = AppLocalizations.of(context)!;
    try {
      // Late init in case startup init failed (e.g. no network then).
      if (!UnityAdsService.isInitialized) {
        await UnityAdsService.init();
      }
      if (!UnityAdsService.isInitialized) {
        throw Exception(t.unityNotReady);
      }
      final loaded = await UnityAdsService.loadRewardedAd();
      if (!loaded) {
        throw Exception(t.adLoadFailed);
      }
      final result = await UnityAdsService.showRewardedAd();
      if (result == UnityAdResult.completed) {
        // Full watch — credit coins server-side.
        final claim = await SupabaseService.claimUnityReward();
        final coins = claim['coins'];
        if (!mounted) return;
        setState(() {
          _message = t.rewardEarned(coins is int ? '$coins' : '0');
        });
      } else if (result == UnityAdResult.skipped) {
        if (!mounted) return;
        setState(() {
          _message = t.adSkipped;
          _isError = true;
        });
      } else {
        throw Exception(t.adLoadFailed);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _message = msg.isEmpty ? t.genericError : msg;
        _isError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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
                  Icon(
                    Icons.play_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.watchAdTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.watchAdSubtitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _watchAd,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_busy ? t.pleaseWait : t.watchAdButton),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isError
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Weekly leaderboard (social proof + competition)
          const LeaderboardWidget(),
          const SizedBox(height: 16),
          Text(
            t.watchAdNote,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
