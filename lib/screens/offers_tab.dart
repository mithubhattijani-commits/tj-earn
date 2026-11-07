import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';
import '../widgets/leaderboard.dart';
import '../widgets/spin_wheel.dart';

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

  // Visit task (Jaani, 7 Nov 2026): the user opens the Nigraan TV
  // Facebook Page or the website, then taps Claim. Reward is for VISITING
  // only — never for following or liking.
  bool _visitBusy = false;
  bool _visitOpened = false;
  String _visitDestination = 'website';
  String? _visitMessage;
  bool _visitIsError = false;

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

  /// Opens a Visit destination in the external browser.
  ///
  /// On a successful open the Claim button unlocks for this session.
  /// The open itself is an OS handoff (no network call, no spinner);
  /// a failed open surfaces [AppLocalizations.visitOpenFailed].
  Future<void> _openVisit(String destination, String url) async {
    if (_visitBusy) return;
    setState(() {
      _visitMessage = null;
      _visitIsError = false;
    });
    final t = AppLocalizations.of(context)!;
    try {
      final Uri uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) {
        throw Exception(t.visitOpenFailed);
      }
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception(t.visitOpenFailed);
      }
      if (!mounted) return;
      setState(() {
        _visitOpened = true;
        _visitDestination = destination;
        _visitMessage = t.visitClaimFirst;
      });
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _visitMessage = msg.isEmpty ? t.genericError : msg;
        _visitIsError = true;
      });
    }
  }

  /// Claims the Visit task reward from the server.
  ///
  /// First-ever visit pays 50 coins, later visits 5 coins once per PKT
  /// day (server-enforced; 409 = already claimed today). The claim is
  /// only enabled after the user opened a destination this session, and
  /// it locks again after every claim attempt so each claim needs a
  /// fresh visit.
  Future<void> _claimVisit() async {
    if (_visitBusy || !_visitOpened) return;
    setState(() {
      _visitBusy = true;
      _visitMessage = null;
      _visitIsError = false;
    });
    final t = AppLocalizations.of(context)!;
    try {
      final Map<String, dynamic> result =
          await SupabaseService.claimVisit(destination: _visitDestination);
      if (!mounted) return;
      final bool already = result['already_claimed'] == true;
      if (already) {
        setState(() {
          _visitMessage = t.visitAlreadyDone;
          _visitIsError = true;
          _visitOpened = false;
        });
        return;
      }
      final Object? coins = result['coins'];
      final String coinsText = coins is int ? '$coins' : '0';
      final bool first = result['first_visit'] == true;
      setState(() {
        _visitMessage = first
            ? t.visitEarnedFirst(coinsText)
            : t.visitEarnedDaily(coinsText);
        _visitOpened = false;
      });
    } catch (e) {
      if (!mounted) return;
      final String msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _visitMessage = msg.isEmpty ? t.genericError : msg;
        _visitIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _visitBusy = false);
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
          // Visit task (Jaani, 7 Nov 2026): visit the Nigraan TV
          // Facebook Page or the website, then claim coins. First visit
          // pays 50 coins, then 5 coins every day. The reward is for
          // VISITING only — following or liking is never required and
          // never rewarded.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.open_in_new,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.visitTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.visitSubtitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _visitBusy
                              ? null
                              : () => _openVisit(
                                    'facebook',
                                    'https://www.facebook.com/1326981980495735',
                                  ),
                          icon: const Icon(Icons.people_outline),
                          label: Text(t.visitFacebookButton),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _visitBusy
                              ? null
                              : () => _openVisit(
                                    'website',
                                    'https://nigraantv.xyz',
                                  ),
                          icon: const Icon(Icons.language),
                          label: Text(t.visitWebsiteButton),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        (_visitBusy || !_visitOpened) ? null : _claimVisit,
                    icon: _visitBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.card_giftcard),
                    label:
                        Text(_visitBusy ? t.pleaseWait : t.visitClaimButton),
                  ),
                  if (_visitMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _visitMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _visitIsError
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
          // Daily spin wheel (Roz Dhan-style engagement)
          const SpinWheel(),
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
