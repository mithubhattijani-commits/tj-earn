/// Remote Config — server-driven in-app content (v1).
///
/// Fail-soft: network -> cache -> bundled defaults. Never blocks startup,
/// never an infinite spinner, never a crash — on any failure the app just
/// uses what it has (APP ROBUSTNESS RULE, Jaani 2 Nov 2026).
///
/// Config URL (live): https://nigraantv.xyz/apps/config/tj-earn.json
/// Operator workflow: see ~/workspace/app-remote-config/REMOTE-CONFIG.md
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Slim notice bar under the header. Shows only when enabled AND
/// the text is non-empty.
class AnnouncementConfig {
  const AnnouncementConfig({this.enabled = false, this.text = ''});

  final bool enabled;
  final String text;

  bool get show => enabled && text.trim().isNotEmpty;

  factory AnnouncementConfig.fromJson(Map<String, dynamic> j) {
    return AnnouncementConfig(
      enabled: j['enabled'] == true,
      text: (j['text'] ?? '').toString(),
    );
  }
}

/// Paid-ad slot card (image + title). Tap opens [actionUrl] in the
/// external browser. Never auto-opens, never blocks the app.
class SponsoredAdConfig {
  const SponsoredAdConfig({
    this.enabled = false,
    this.title = '',
    this.imageUrl = '',
    this.actionUrl = '',
  });

  final bool enabled;
  final String title;
  final String imageUrl;
  final String actionUrl;

  bool get show =>
      enabled && title.trim().isNotEmpty && actionUrl.trim().isNotEmpty;

  factory SponsoredAdConfig.fromJson(Map<String, dynamic> j) {
    return SponsoredAdConfig(
      enabled: j['enabled'] == true,
      title: (j['title'] ?? '').toString(),
      imageUrl: (j['image_url'] ?? '').toString(),
      actionUrl: (j['action_url'] ?? '').toString(),
    );
  }
}

/// Kill-switch: when enabled and the installed versionCode is below
/// [minVersionCode], the app shows a non-dismissible update dialog
/// wired to the existing in-app updater. Use only for critical /
/// security releases.
class ForceUpdateConfig {
  const ForceUpdateConfig({this.enabled = false, this.minVersionCode = 0});

  final bool enabled;
  final int minVersionCode;

  factory ForceUpdateConfig.fromJson(Map<String, dynamic> j) {
    final dynamic raw = j['min_version_code'];
    return ForceUpdateConfig(
      enabled: j['enabled'] == true,
      minVersionCode: raw is int ? raw : int.tryParse('$raw') ?? 0,
    );
  }
}

/// Whole-document config object.
class RemoteConfig {
  const RemoteConfig({
    this.displayName = '',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
  });

  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;

  static const RemoteConfig defaults = RemoteConfig();

  static Map<String, dynamic> _section(
      Map<String, dynamic> j, String key) {
    final dynamic raw = j[key];
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    return RemoteConfig(
      displayName: (j['display_name'] ?? '').toString(),
      logoUrl: (j['logo_url'] ?? '').toString(),
      announcement: AnnouncementConfig.fromJson(_section(j, 'announcement')),
      sponsoredAd: SponsoredAdConfig.fromJson(_section(j, 'sponsored_ad')),
      forceUpdate: ForceUpdateConfig.fromJson(_section(j, 'force_update')),
    );
  }
}

/// Singleton service. UI listens to [notifier] so a fresh fetch updates
/// the screen without a restart.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  /// TJ Earn's config URL — set per app.
  static const String configUrl =
      'https://nigraantv.xyz/apps/config/tj-earn.json';

  static const Duration fetchTimeout = Duration(seconds: 8);
  static const Duration refreshInterval = Duration(hours: 6);
  static const String _cacheKey = 'remote_config_json_v1';
  static const String _cacheTimeKey = 'remote_config_time_v1';

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier<RemoteConfig>(RemoteConfig.defaults);

  RemoteConfig get config => notifier.value;

  /// Call once at startup, WITHOUT awaiting it (fire-and-forget).
  /// Loads the local cache first (fast), then refreshes from the network
  /// in the background. Never blocks the first frame.
  Future<void> init() async {
    await _loadFromCache();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int ts = prefs.getInt(_cacheTimeKey) ?? 0;
    final int age = DateTime.now().millisecondsSinceEpoch - ts;
    if (ts == 0 || age > refreshInterval.inMilliseconds) {
      unawaited(_refresh()); // never block startup
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          notifier.value =
              RemoteConfig.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      notifier.value = RemoteConfig.defaults;
    }
  }

  Future<void> _refresh() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = fetchTimeout;
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(configUrl));
      final HttpClientResponse resp =
          await req.close().timeout(fetchTimeout);
      if (resp.statusCode != HttpStatus.ok) {
        return;
      }
      final String body = await resp.transform(utf8.decoder).join();
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map) {
        return;
      }
      final RemoteConfig parsed =
          RemoteConfig.fromJson(decoded.cast<String, dynamic>());
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      await prefs.setInt(
          _cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      notifier.value = parsed;
    } catch (_) {
      // Fail-soft: keep cache/defaults.
    } finally {
      client?.close(force: true);
    }
  }
}
