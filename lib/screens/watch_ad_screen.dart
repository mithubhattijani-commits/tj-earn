import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';

/// Dedicated Watch Ad screen (Unity rewarded video).
///
/// Prominent "Watch Ad — Earn 10 Coins" entry point from the Home tab's
/// Rewards section (Jaani, 31 Oct 2026). The user watches a full rewarded
/// video; coins are credited server-side by the `claim-unity-reward`
/// Edge Function — the app never writes to the ledger.
///
/// Rewards are coins (virtual currency), never cash — per Unity policy.
class WatchAdScreen extends StatefulWidget {
  const WatchAdScreen({super.key});

  @override
  State<WatchAdScreen> createState() => _WatchAdScreenState();
}

class _WatchAdScreenState extends State<WatchAdScreen> {
  bool _busy = false;
  String? _message;
  bool _isError = false;
  int? _adsLeft;

  @override
  void initState() {
    super.initState();
    _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final int? left = await SupabaseService.getUnityAdsRemainingToday();
    if (!mounted) return;
    setState(() {
      _adsLeft = left;
    });
  }

  Future<void> _watchAd() async {
    if (_busy) return;
    final t = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
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
      if (!mounted) return;
      if (result == UnityAdResult.completed) {
        // Full watch — credit coins server-side.
        final Map<String, dynamic> claim =
            await SupabaseService.claimUnityReward();
        final Object? coins = claim['coins'];
        final Object? remaining = claim['remaining'];
        if (!mounted) return;
        setState(() {
          _message = t.rewardEarned(coins is int ? '$coins' : '0');
          if (remaining is int) _adsLeft = remaining;
        });
      } else if (result == UnityAdResult.skipped) {
        setState(() {
          _message = t.adSkipped;
          _isError = true;
        });
      } else {
        throw Exception(t.adLoadFailed);
      }
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      final String friendly = msg.contains('cap_reached')
          ? t.adLimitReached
          : msg.contains('too_soon')
              ? t.claimTooSoon
              : msg;
      setState(() {
        _message = friendly.isEmpty ? t.genericError : friendly;
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
    return Scaffold(
      appBar: AppBar(title: Text(t.watchAdTile)),
      body: SingleChildScrollView(
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
                      t.watchAdRewardLine,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (_adsLeft != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        t.adsLeftToday('$_adsLeft'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      t.watchAdSubtitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed:
                          (_busy || _adsLeft == 0) ? null : _watchAd,
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
            Text(
              t.watchAdNote,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
