import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app Adsterra banner (dual-ad system, Jaani 2 Nov 2026).
///
/// A small WebView that loads the lightweight
/// https://nigraantv.xyz/earn/app-banner/ page, which carries only an
/// Adsterra 320x50 banner (no popunders, no heavy JS). This gives a real
/// Adsterra impression on every app visit, complementing the Unity ads
/// shown in-app.
///
/// - Fixed 320x60 footprint; hidden gracefully on load error or offline.
/// - Never blocks the UI; no JavaScript bridge back into the app.
/// - Taps open in the external browser via the page's own links.
class AdBannerWebView extends StatefulWidget {
  const AdBannerWebView({super.key});

  @override
  State<AdBannerWebView> createState() => _AdBannerWebViewState();
}

class _AdBannerWebViewState extends State<AdBannerWebView> {
  late final WebViewController _controller;
  bool _failed = false;

  static const String _bannerUrl = 'https://nigraantv.xyz/earn/app-banner/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            // Offline or blocked: hide the banner instead of showing
            // an error box. Never throws.
            if (mounted) setState(() => _failed = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(_bannerUrl));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: WebViewWidget(controller: _controller),
    );
  }
}
