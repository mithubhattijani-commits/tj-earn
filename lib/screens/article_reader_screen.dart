import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/supabase_service.dart';

/// In-app article reader (Jaani, 3 Nov 2026).
/// Opens the nigraantv.xyz article in a WebView. A countdown enforces the
/// minimum read time (matching the website's rule); then the user taps
/// "Claim +10 Coins" which calls the shared `submit-reading` Edge Function.
/// Returns true if a reward was claimed (so the list can refresh).
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
      await SupabaseService.submitReading(widget.articleId);
      if (!mounted) return;
      setState(() {
        _claimed = true;
        _claiming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('+10 coins earned!')),
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
            ? 'Daily reading limit reached (5/day).'
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
