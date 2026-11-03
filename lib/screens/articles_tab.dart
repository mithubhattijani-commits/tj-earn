import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/supabase_service.dart';
import 'article_reader_screen.dart';

/// "Read Articles" tab (Jaani, 3 Nov 2026): website <-> app integration.
/// Lists latest nigraantv.xyz articles. Tapping one opens it in an in-app
/// WebView; after the minimum read time the user can claim the reading
/// reward (10 coins, cap 5/day) via the same `submit-reading` Edge Function
/// the website uses — so the balance is shared.
class ArticlesTab extends StatefulWidget {
  const ArticlesTab({super.key});

  @override
  State<ArticlesTab> createState() => _ArticlesTabState();
}

class _Article {
  final String id;
  final String title;
  _Article(this.id, this.title);
}

class _ArticlesTabState extends State<ArticlesTab> {
  List<_Article> _articles = [];
  bool _loading = true;
  String? _error;
  int? _remainingToday;

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
            articles.add(_Article(id, title));
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load articles. Pull to retry.';
        _loading = false;
      });
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
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = _articles[i];
                      return ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(a.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.monetization_on_outlined,
                                size: 16, color: Colors.amber),
                            SizedBox(width: 4),
                            Text('+10',
                                style: TextStyle(color: Colors.amber)),
                          ],
                        ),
                        onTap: () async {
                          final claimed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ArticleReaderScreen(
                                articleId: a.id,
                                title: a.title,
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
}
