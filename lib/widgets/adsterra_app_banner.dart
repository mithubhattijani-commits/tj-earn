import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Adsterra banner loaded from the website (dual-ad system, Jaani 2 Nov 2026).
///
/// Every app visit loads https://nigraantv.xyz/earn/app-banner/ — a
/// lightweight page carrying ONLY the Adsterra 320x50 banner (unit 31853146).
/// This gives a real website ad impression on every app visit, alongside
/// the Unity ads shown in-app.
///
/// - Never blocks the UI: hidden on load error or offline.
/// - No popunders, no tracking beyond the banner itself.
///
/// ANR FIX (Jaani, 2 Nov 2026): the platform WebView is constructed natively
/// on Android's main thread, and the FIRST android.webkit.WebView creation on
/// a slow device can block that thread for 5+ seconds (WebView provider
/// load) — Android then raises "isn't responding". So the controller is NOT
/// created in initState on the startup path; it is built only after the first
/// frame plus an idle delay, when the app is already fully interactive.
class AdsterraAppBanner extends StatefulWidget {
  const AdsterraAppBanner({super.key});

  @override
  State<AdsterraAppBanner> createState() => _AdsterraAppBannerState();
}

class _AdsterraAppBannerState extends State<AdsterraAppBanner> {
  static const String _bannerUrl = 'https://nigraantv.xyz/earn/app-banner/';

  WebViewController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        try {
          final WebViewController c = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0x00000000))
            ..setNavigationDelegate(
              NavigationDelegate(
                onWebResourceError: (_) {
                  if (mounted) setState(() => _failed = true);
                },
              ),
            )
            ..loadRequest(Uri.parse(_bannerUrl));
          if (!mounted) return;
          setState(() => _controller = c);
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final WebViewController? c = _controller;
    if (c == null) return const SizedBox.shrink();
    return Container(
      width: 320,
      height: 50,
      alignment: Alignment.center,
      child: WebViewWidget(controller: c),
    );
  }
}
