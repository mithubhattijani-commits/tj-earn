import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/unity_ads_service.dart';
import 'article_reader_screen.dart';

/// "Read Articles" tab (Jaani, 3 Nov 2026): website <-> app integration.
/// Lists latest nigraantv.xyz articles. Tapping one opens it in an in-app
/// WebView; after the minimum read time the user can claim the reading
/// reward (5 coins per UNIQUE article, cap 200/day — compliant model,
/// v1.0.25) via the `submit-reading` Edge Function.
///
/// Opening an article may also show a NON-REWARDED interstitial video
/// (every Nth open, min gap — remote-config earn rates). The ad is never
/// a condition for any coin grant.
///
/// Bilingual (Jaani, 6 Nov 2026): the feed carries both Urdu and English
/// articles (English ones have en:true). Filter chips at the top of the
/// list — All / English / اردو — default All, so both languages stay
/// visible; each row carries a small language badge (EN / اردو). The
/// reader screen opens the site chrome in the article's language via the
/// site's own setLang() (see ArticleReaderScreen).
class ArticlesTab extends StatefulWidget {
  const ArticlesTab({super.key});

  @override
  State<ArticlesTab> createState() => _ArticlesTabState();
}

class _Article {
  final String id;
  final String title;
  final bool isEnglish;
  _Article(this.id, this.title, {this.isEnglish = false});
}

enum _LangFilter { all, en, ur }

class _ArticlesTabState extends State<ArticlesTab> {
  List<_Article> _articles = [];
  bool _loading = true;
  String? _error;
  int? _remainingToday;
  _LangFilter _filter = _LangFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch latest articles from the website's lite feed.
      final res = await http
          .get(Uri.parse('https://nigraantv.xyz/articles-lite.js'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      // articles-lite.js is: window.ARTICLES_DATA = [ {...}, {...} ];
      final start = body.indexOf('[');
      final end = body.lastIndexOf(']');
      if (start < 0 || end < 0) throw Exception('bad feed');
      final list = json.decode(body.substring(start, end + 1)) as List;
      final articles = <_Article>[];
      for (final item in list.take(30)) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final title = item['title']?.toString() ?? '';
          if (id.isNotEmpty && title.isNotEmpty) {
            articles.add(_Article(id, title,
                isEnglish: item['en'] == true));
          }
        }
      }
      // Check remaining reading claims today (shared with website).
      int? remaining;
      try {
        remaining = await SupabaseService.getReadingRemaining();
      } catch (_) {
        // Non-fatal: list still works, claim button will surface errors.
      }
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _remainingToday = remaining;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Network timed out. Pull to retry.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load articles. Pull to retry.';
        _loading = false;
      });
    }
  }

  /// Articles visible under the current language filter (default: all).
  List<_Article> get _visible {
    switch (_filter) {
      case _LangFilter.en:
        return _articles.where((a) => a.isEnglish).toList();
      case _LangFilter.ur:
        return _articles.where((a) => !a.isEnglish).toList();
      case _LangFilter.all:
        return _articles;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read Articles'),
        actions: [
          if (_remainingToday != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$_remainingToday left today',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : ListView.separated(
                    // Item 0 is the language filter row; the rest are
                    // articles. Keeps the ListView the direct child of
                    // RefreshIndicator so pull-to-refresh keeps working.
                    itemCount: _visible.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: Row(
                            children: [
                              _filterChip('All', _LangFilter.all),
                              const SizedBox(width: 8),
                              _filterChip('English', _LangFilter.en),
                              const SizedBox(width: 8),
                              _filterChip('اردو', _LangFilter.ur),
                            ],
                          ),
                        );
                      }
                      final a = _visible[i - 1];
                      return ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(a.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _langBadge(a.isEnglish),
                            const SizedBox(width: 8),
                            const Icon(Icons.monetization_on_outlined,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            const Text('+5',
                                style: TextStyle(color: Colors.amber)),
                          ],
                        ),
                        onTap: () async {
                          // Non-rewarded interstitial between articles
                          // (compliant model, v1.0.25): gated by the
                          // remote-config earn rates. Fire-and-forget —
                          // the reader opens immediately; the ad never
                          // gates any coin grant.
                          final rates = RemoteConfigService
                              .instance.config.earnRates;
                          unawaited(
                            UnityAdsService.maybeShowArticleInterstitial(
                              everyNthArticle:
                                  rates.interstitialEveryNthArticle,
                              minGap: Duration(
                                minutes: rates.interstitialMinGapMinutes,
                              ),
                            ),
                          );
                          final claimed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ArticleReaderScreen(
                                articleId: a.id,
                                title: a.title,
                                isEnglish: a.isEnglish,
                              ),
                            ),
                          );
                          if (claimed == true) _load();
                        },
                      );
                    },
                  ),
      ),
    );
  }

  Widget _filterChip(String label, _LangFilter value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) {
        if (_filter != value) setState(() => _filter = value);
      },
    );
  }

  Widget _langBadge(bool isEnglish) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isEnglish ? 'EN' : 'اردو',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }
}
