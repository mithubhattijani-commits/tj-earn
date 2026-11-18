import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/supabase_service.dart';

/// Play & Earn (RapidoReach wall, v1.0.25) — Games section.
///
/// The wall opens in an in-app WebView. The signed wall URL comes from
/// the `rapidoreach-wall-url` Edge Function, which builds the
/// RapidoReach UID server-side from the logged-in user's Supabase UUID
/// (the App Key signs the UID, so it never enters the app).
///
/// Compliant model (Unity ticket #00945584): this screen NEVER promises
/// or grants coins. The wall shows its own offers; completions credit
/// through the `rapidoreach-postback` Edge Function into the server
/// ledger, and the balance refreshes on Home.
///
/// Fail-soft: if the function is not deployed / not configured / the
/// network fails, this screen shows a friendly "not available yet"
/// message with a retry button — never a crash or a blank WebView.
/// No JavaScript bridge back into the app. Back navigation: Android
/// back (and the AppBar back button) first walks the wall's own
/// history, then leaves the screen.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  WebViewController? _controller;
  bool _pageLoading = true;
  int _progress = 0;
  String? _errorKey; // 'unavailable' | 'failed'

  @override
  void initState() {
    super.initState();
    _loadWall();
  }

  Future<void> _loadWall() async {
    if (!mounted) return;
    setState(() {
      _pageLoading = true;
      _progress = 0;
      _errorKey = null;
      _controller = null;
    });
    try {
      final String url = await SupabaseService.getRapidoreachWallUrl()
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int p) {
              if (mounted) setState(() => _progress = p);
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() {
                  _pageLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              // Main-frame failures only: a failed sub-resource
              // (tracking pixel, image) must not kill the wall.
              if (error.isForMainFrame == true && mounted) {
                setState(() {
                  _errorKey = 'failed';
                  _pageLoading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
      setState(() {
        _controller = controller;
      });
    } catch (_) {
      // The function answers 500 "not configured" until the server
      // side is ready — same friendly state as any other failure.
      if (!mounted) return;
      setState(() {
        _errorKey = 'unavailable';
        _pageLoading = false;
      });
    }
  }

  /// Back button: walk the wall's history first, leave the screen
  /// only when there is no history left.
  Future<bool> _onPop() async {
    final WebViewController? controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  Widget _errorView(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_esports_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              _errorKey == 'failed'
                  ? t.gamesLoadFailed
                  : t.gamesUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadWall,
              child: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final WebViewController? controller = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        final bool shouldPop = await _onPop();
        if (!shouldPop) return;
        // `context` here is build's BuildContext parameter, so the
        // guard is context.mounted (not the State's mounted).
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.gamesTitle),
        ),
        body: _errorKey != null
            ? _errorView(t)
            : controller == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(t.gamesLoading),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          t.gamesNote,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (_pageLoading)
                        LinearProgressIndicator(value: _progress / 100),
                      Expanded(
                        child: WebViewWidget(controller: controller),
                      ),
                    ],
                  ),
      ),
    );
  }
}
