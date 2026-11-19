import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/validation.dart' show formatCoinsAsPkr;

/// In-app article reader (Jaani, 3 Nov 2026).
/// Opens the nigraantv.xyz article in a WebView. A countdown enforces the
/// minimum read time (matching the website's rule); then the user taps
/// "Claim +5 Coins" which calls the shared `submit-reading` Edge Function.
/// Returns true if a reward was claimed (so the list can refresh).
///
/// Compliant model (v1.0.25): 5 coins per UNIQUE article, cap 200/day
/// (server-enforced via app_config). Before claiming, the reader also
/// checks the user actually scrolled through the article (best-effort:
/// a page that cannot scroll, or a JS failure, passes — the server's
/// 30s dwell check remains the hard anti-farm gate).
///
/// Bilingual (Jaani, 6 Nov 2026): the site has no URL lang param — its
/// language lives only in localStorage ('ntv-lang') and its own global
/// setLang() switches the chrome live (verified in dist/index.html). A
/// fresh WebView defaults to Urdu and ntv-lang persists across reader
/// screens, so on every page finish we call setLang() with this
/// article's language (English articles: 'en', Urdu articles: 'ur').
/// The article body itself always renders in the article's own language.
class ArticleReaderScreen extends StatefulWidget {
  final String articleId;
  final String title;
  final bool isEnglish;

  const ArticleReaderScreen({
    super.key,
    required this.articleId,
    required this.title,
    this.isEnglish = false,
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
  bool _langApplied = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _applyArticleLanguage(),
        ),
      )
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

  /// Switch the site chrome to this article's language using the site's
  /// own global setLang(). Runs once per page load.
  void _applyArticleLanguage() {
    if (_langApplied) return;
    _langApplied = true;
    final lang = widget.isEnglish ? 'en' : 'ur';
    _controller.runJavaScript(
      "if (typeof setLang === 'function') setLang('$lang');",
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Best-effort scroll check: true when the user scrolled through the
  /// article, or when the page is not meaningfully scrollable, or when
  /// the check itself cannot run (fail open — the server's 30s dwell
  /// check is the hard gate; this only stops zero-scroll claims).
  Future<bool> _hasScrolled() async {
    try {
      final Object result =
          await _controller.runJavaScriptReturningResult(
        '(function(){var d=document.documentElement;'
        'var max=Math.max(d.scrollHeight,'
        'document.body?document.body.scrollHeight:0)-window.innerHeight;'
        'if(max<=80) return true;'
        'return (window.scrollY||d.scrollTop||0)>80;})()',
      );
      if (result is bool) return result;
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Coins per article from remote config (default 5). The Rs value
  /// is always shown next to it (user order 19 Nov 2026): every cash
  /// earning displays its Rs value, "5 coins = Rs 0.05".
  int get _rewardCoins =>
      RemoteConfigService.instance.config.earnRates.readRewardCoins;

  Future<void> _claim() async {
    setState(() {
      _claiming = true;
      _claimError = null;
    });
    if (!await _hasScrolled()) {
      if (!mounted) return;
      setState(() {
        _claimError = 'Please scroll through the article before claiming.';
        _claiming = false;
      });
      return;
    }
    try {
      await SupabaseService.submitReading(widget.articleId);
      if (!mounted) return;
      setState(() {
        _claimed = true;
        _claiming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '+$_rewardCoins coins earned! '
            '(${formatCoinsAsPkr(_rewardCoins)})',
          ),
        ),
      );
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
            ? 'Daily reading limit reached (200/day).'
            : 'Could not claim. Try again.';
        _claiming = false;
      });
    }
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
                        ? Text(
                            '+$_rewardCoins coins claimed! '
                            '(${formatCoinsAsPkr(_rewardCoins)})',
                            style: const TextStyle(color: Colors.green),
                          )
                        : _secondsLeft > 0
                            ? Text(
                                'Read for $_secondsLeft s to earn '
                                '+$_rewardCoins coins '
                                '(${formatCoinsAsPkr(_rewardCoins)})',
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
                        : Text('Claim +$_rewardCoins'),
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
