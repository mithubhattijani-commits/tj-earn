import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';

/// In-app article reader (Jaani, 3 Nov 2026).
/// Opens the nigraantv.xyz article in a WebView. A countdown enforces the
/// minimum read time (matching the website's rule); then the user taps
/// "Claim +10 Coins" which calls the shared `submit-reading` Edge Function.
/// Returns true if a reward was claimed (so the list can refresh).
///
/// DOUBLE REWARD (Jaani, 4 Nov 2026): after a successful claim the user
/// is OFFERED (never forced) one Unity rewarded video to double the
/// coins. The bonus is credited server-side by the `claim-double-bonus`
/// Edge Function — the UI only shows what the server actually credited.
class ArticleReaderScreen extends StatefulWidget {
  final String articleId;
  final String title;

  const ArticleReaderScreen({
    super.key,
    required this.articleId,
    required this.title,
  });

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  late final WebViewController _controller;
  static const int _minReadSeconds = 30;
  int _secondsLeft = _minReadSeconds;
  Timer? _timer;
  bool _claiming = false;
  String? _claimError;
  bool _claimed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse('https://nigraantv.xyz/#/article/${widget.articleId}'),
      );
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _claim() async {
    setState(() {
      _claiming = true;
      _claimError = null;
    });
    try {
      final int coins = await SupabaseService.submitReading(widget.articleId);
      if (!mounted) return;
      setState(() {
        _claimed = true;
        _claiming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$coins coins earned!')),
      );
      // Optional double-reward — the user's choice, never forced.
      await _offerDoubleReward(coins);
      if (!mounted) return;
      // Pop back with claimed=true after a beat.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _claimError = 'Network timed out. Try again.';
        _claiming = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _claimError = msg.contains('429') || msg.contains('cap')
            ? 'Daily reading limit reached (5/day).'
            : 'Could not claim. Try again.';
        _claiming = false;
      });
    }
  }

  /// Double-reward offer (Jaani, 4 Nov 2026).
  ///
  /// Shows the opt-in dialog, then (only on tap) a Unity rewarded video.
  /// On a FULL watch, credits the bonus via `claim-double-bonus` and
  /// returns true when the server actually credited it. Every wait is
  /// bounded — the UI never hangs on ads or the network. Skipping the
  /// video or declining the dialog is a clean no-op.
  Future<bool> _offerDoubleReward(int coins) async {
    final t = AppLocalizations.of(context)!;
    final bool? want = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.doubleRewardTitle),
        content: Text(t.doubleRewardBody('$coins')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.doubleRewardNoThanks),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.play_arrow),
            label: Text(t.doubleRewardButton),
          ),
        ],
      ),
    );
    if (want != true || !mounted) return false;

    // Late init in case startup init failed (e.g. no network then).
    if (!UnityAdsService.isInitialized) {
      await UnityAdsService.init();
    }
    if (!mounted) return false;
    // Bounded load — a stall surfaces as false, never a hang.
    final bool loaded = await UnityAdsService.loadRewardedAd();
    if (!mounted) return false;
    if (!loaded) {
      _showDoubleError(t.doubleRewardAdFailed);
      return false;
    }
    final UnityAdResult result = await UnityAdsService.showRewardedAd();
    if (!mounted) return false;
    if (result != UnityAdResult.completed) {
      if (result == UnityAdResult.failed) {
        _showDoubleError(t.doubleRewardAdFailed);
      }
      // Skipped: no error, no bonus — the user chose not to finish.
      return false;
    }
    // Full watch — credit the bonus server-side. The server is the
    // authority: only a credited response counts as earned.
    try {
      final int bonus =
          await SupabaseService.claimDoubleBonus(ref: widget.articleId);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.doubleRewardEarned('$bonus'))),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      _showDoubleError(t.doubleRewardClaimFailed);
      return false;
    }
  }

  void _showDoubleError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canClaim = _secondsLeft == 0 && !_claimed;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 4,
                      offset: Offset(0, -1),
                      color: Colors.black12)
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _claimed
                        ? const Text('+10 coins claimed!',
                            style: TextStyle(color: Colors.green))
                        : _secondsLeft > 0
                            ? Text(
                                'Read for $_secondsLeft s to earn +10 coins',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : _claimError != null
                                ? Text(_claimError!,
                                    style:
                                        const TextStyle(color: Colors.red))
                                : const Text(
                                    'Finished reading? Claim your reward:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: canClaim && !_claiming ? _claim : null,
                    child: _claiming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Text('Claim +10'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
