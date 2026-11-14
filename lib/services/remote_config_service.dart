// Remote Config — server-driven in-app content (v1).
//
// Fail-soft: network -> cache -> bundled defaults. Never blocks startup,
// never an infinite spinner, never a crash — on any failure the app just
// uses what it has (APP ROBUSTNESS RULE, Jaani 2 Nov 2026).
//
// Config URL (live): https://nigraantv.xyz/apps/config/tj-earn.json
// Operator workflow: see ~/workspace/app-remote-config/REMOTE-CONFIG.md
//
// Polling (Task D, 12 Nov 2026): the old 6h TTL is gone — the config is
// re-fetched fresh on launch, on resume, and every ~60s (see
// [RemoteConfigService.refresh] / [RemoteConfigService.startPolling]).
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
    this.imageUrl = '',
    this.title = '',
    this.actionUrl = '',
  });

  final bool enabled;
  final String imageUrl;
  final String title;
  final String actionUrl;

  bool get show => enabled && imageUrl.trim().isNotEmpty;

  factory SponsoredAdConfig.fromJson(Map<String, dynamic> j) {
    return SponsoredAdConfig(
      enabled: j['enabled'] == true,
      imageUrl: (j['image_url'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      actionUrl: (j['action_url'] ?? '').toString(),
    );
  }
}

/// Kill-switch (plan app/src/main/AndroidManifest.xml `isUpdateRequired`
/// BUT for sideloaded FOSS apps the dialog has to sit in-app). When
/// [enabled] is true and the app's versionCode is below [minVersionCode],
/// the app shows the update dialog wired to the existing in-app updater.
class ForceUpdateConfig {
  const ForceUpdateConfig({this.enabled = false, this.minVersionCode = 0});
  final bool enabled;
  final int minVersionCode;

  factory ForceUpdateConfig.fromJson(Map<String, dynamic> j) {
    return ForceUpdateConfig(
      enabled: j['enabled'] == true,
      minVersionCode: (j['min_version_code'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Per-zone ad ON/OFF switches from the website admin panel
/// (tj-earn.json "ads" object). Doner pattern, 14 Nov 2026.
/// Every switch defaults to true (fail-open): a missing key or an
/// older config never hides an ad. When a zone is false its banner
/// slot renders nothing (zero height).
///
/// MASTER SWITCH: ads_enabled (default true) gates ALL Unity ads at
/// once — when false, no Unity ad shows anywhere regardless of the
/// zones. The user flips it from the admin panel with no new build.
/// rewarded_enabled gates the opt-in rewarded video the same way.
class AdsConfig {
  const AdsConfig({
    this.adsEnabled = true,
    this.bannerHome = true,
    this.bannerArticles = true,
    this.bannerReferral = true,
    this.bannerWithdraw = true,
    this.bannerSettings = true,
    this.bannerAdmin = true,
    this.bannerWatchAd = true,
    this.bannerArticleReader = true,
    this.bannerTasks = true,
    this.rewardedEnabled = true,
  });

  final bool adsEnabled;
  final bool bannerHome;
  final bool bannerArticles;
  final bool bannerReferral;
  final bool bannerWithdraw;
  final bool bannerSettings;
  final bool bannerAdmin;
  final bool bannerWatchAd;
  final bool bannerArticleReader;
  final bool bannerTasks;
  final bool rewardedEnabled;

  static bool _on(Map<String, dynamic> j, String key) =>
      j[key] is bool ? j[key] as bool : true;

  factory AdsConfig.fromJson(Map<String, dynamic> j) => AdsConfig(
        adsEnabled: _on(j, 'ads_enabled'),
        bannerHome: _on(j, 'banner_home'),
        bannerArticles: _on(j, 'banner_articles'),
        bannerReferral: _on(j, 'banner_referral'),
        bannerWithdraw: _on(j, 'banner_withdraw'),
        bannerSettings: _on(j, 'banner_settings'),
        bannerAdmin: _on(j, 'banner_admin'),
        bannerWatchAd: _on(j, 'banner_watch_ad'),
        bannerArticleReader: _on(j, 'banner_article_reader'),
        bannerTasks: _on(j, 'banner_tasks'),
        rewardedEnabled: _on(j, 'rewarded_enabled'),
      );
}

class RemoteConfig {
  const RemoteConfig({
    this.displayName = 'TJ Earn',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
    this.ads = const AdsConfig(),
  });

  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;
  final AdsConfig ads;

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    return RemoteConfig(
      displayName: (j['display_name'] as String?)?.trim().isNotEmpty == true
          ? (j['display_name'] as String).trim()
          : 'TJ Earn',
      logoUrl: (j['logo_url'] ?? '').toString(),
      announcement: j['announcement'] is Map<String, dynamic>
          ? AnnouncementConfig.fromJson(
              j['announcement'] as Map<String, dynamic>,
            )
          : const AnnouncementConfig(),
      sponsoredAd: j['sponsored_ad'] is Map<String, dynamic>
          ? SponsoredAdConfig.fromJson(
              j['sponsored_ad'] as Map<String, dynamic>,
            )
          : const SponsoredAdConfig(),
      forceUpdate: j['force_update'] is Map<String, dynamic>
          ? ForceUpdateConfig.fromJson(
              j['force_update'] as Map<String, dynamic>,
            )
          : const ForceUpdateConfig(),
      ads: j['ads'] is Map<String, dynamic>
          ? AdsConfig.fromJson(j['ads'] as Map<String, dynamic>)
          : const AdsConfig(),
    );
  }
}

/// Singleton service. UI listens to [notifier] so a fresh fetch updates
/// the screen without a restart.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  static const _cacheKey = 'remote_config_json_v1';
  static const _url = 'https://nigraantv.xyz/apps/config/tj-earn.json';
  static const Duration _fetchTimeout = Duration(seconds: 8);

  /// Poll interval (Task D, 12 Nov 2026): the old 6-hour TTL is gone.
  /// Remote config is small and admin-driven, so it is fetched fresh on
  /// launch, on resume, and every ~60s by [startPolling]. No connectivity
  /// plugin is used (none is in pubspec): a failed fetch keeps the last
  /// good cache, and the next poll / resume retry picks the config up as
  /// soon as the network is back — that is the reconnect path.
  static const Duration refreshInterval = Duration(seconds: 60);

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier(const RemoteConfig());

  RemoteConfig get config => notifier.value;

  Timer? _pollTimer;
  bool _refreshing = false;

  /// Loads the cache first (fast), then ALWAYS fetches fresh from the
  /// network — no TTL gate anymore — and starts the ~60s poll. Never
  /// blocks the first frame; failures stay silent and keep the cache.
  Future<void> init() async {
    await _loadFromCache();
    // Fetch on each cold start. Fire-and-forget: the cached config is
    // already on screen; the network result lands via [notifier].
    unawaited(_refresh());
    startPolling();
  }

  /// Public refresh: fetch the config now. Called on app resume (by
  /// MainShell) and by the poll timer. Safe to call any time — a fetch
  /// already in flight is skipped instead of stacking.
  Future<void> refresh() => _refresh();

  /// Start the ~60s background poll. Idempotent: restarts the timer.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      refreshInterval,
      (_) => unawaited(_refresh()),
    );
  }

  /// Stop the background poll (called when the shell goes away).
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        notifier.value = RemoteConfig.fromJson(parsed);
      }
    } catch (_) {
      // Corrupt cache is ignored: defaults survive.
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _fetchTimeout;
      final request = await client.getUrl(Uri.parse(_url));
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode != HttpStatus.ok) return;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return;
      final remote = RemoteConfig.fromJson(parsed);
      notifier.value = remote;
      // Save the fresh config — survives the next cold start.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
    } catch (_) {
      // Fail-soft: keep cache/defaults.
    } finally {
      _refreshing = false;
      client?.close(force: true);
    }
  }
}
