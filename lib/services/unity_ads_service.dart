import 'dart:async';
import 'package:flutter/material.dart';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

/// Unity Ads integration for TJ Earn (compliant model, v1.0.25).
///
/// COMPLIANT MODEL (17 Nov 2026, Unity ticket #00945584): coins-to-cash
/// via rewarded ads is PROHIBITED on self-serve Unity Ads — rewards for
/// watching ads must be in-app virtual only, never cash. TJ Earn pays
/// cash for READING, so NO coin may ever come from any ad view. There is
/// deliberately no rewarded placement in this service anymore: no
/// `BP_Rewarded_Android`, no reward callback, no coin grant path.
///
/// What remains (all non-rewarded, earning only):
/// - Game ID: 800417967 (Android, "TJ Earn" project)
/// - Banner placement: BP_Banner_Android (Active) — passive bottom slot.
/// - Interstitial placement: BP_Interstitial_Android (Active) — shown
///   between articles via [maybeShowArticleInterstitial], gated by the
///   remote-config earn rates (every Nth article, min gap). Never
///   rewarded, never tied to any coin grant.
/// - App Open placement: BP_AppOpen_Android (Active) — cold start only.
///
/// Test mode is ON for development. Flip [testMode] to false for
/// production builds.
class UnityAdsService {
  static const String gameId = '800417967';

  /// Dual-ad system (Jaani, 2 Nov 2026): every app visit + every coin
  /// claim shows a Unity ad. Interstitial after claims, App Open on launch.
  /// Placement IDs follow the existing BP_ naming convention.
  ///
  /// Compliant model (v1.0.25): the rewarded placement is GONE — see the
  /// class doc. Only the non-rewarded placements remain.
  static const String interstitialPlacementId = 'BP_Interstitial_Android';
  static const String appOpenPlacementId = 'BP_AppOpen_Android';
  static const String bannerPlacementId = 'BP_Banner_Android';

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

  /// ADS BACK ON (Jaani, 2 Nov 2026): the v1.0.9 diagnostic (ads fully
  /// off) proved the ANR is NOT ad-related — kill-switch lifted on his
  /// explicit order ("ads phir ON kar dein ge").
  static const bool adsEnabled = true;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;

  /// Whether the SDK initialized successfully.
  static bool get isInitialized => _initialized;

  /// Whether init was attempted and failed (so the UI can explain why
  /// the Watch Ad button is unavailable).
  static bool get initFailed => _initFailed;

  /// Initialize the Unity Ads SDK. Safe to call at app startup and
  /// again later; a call while an attempt is in flight is a no-op.
  /// Never throws.
  ///
  /// RETRY (Jaani, 8 Nov 2026 — a failed first init killed ads for the
  /// whole session): a failed or timed-out attempt now marks the init
  /// as failed instead of stuck, so the next call retries instead of
  /// returning immediately.
  static Future<void> init() async {
    if (!adsEnabled) return;
    if (_initialized) return;
    if (_initStarted && !_initFailed) return;
    _initStarted = true;
    _initFailed = false;
    try {
      final completer = Completer<void>();
      UnityAds.init(
        gameId: gameId,
        testMode: testMode,
        onComplete: () {
          _initialized = true;
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (error, message) {
          _initFailed = true;
          if (!completer.isCompleted) completer.complete();
        },
      );
      // Don't block startup forever — give init up to 10s.
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _initFailed = true;
        },
      );
      if (!_initialized && !_initFailed) {
        // Neither callback fired within 10s: treat as failed so a
        // later call can retry.
        _initFailed = true;
      }
    } catch (_) {
      _initFailed = true;
    }
  }

  /// Articles opened since the last interstitial (session counter).
  static int _articlesOpenedSinceAd = 0;

  /// When the last interstitial was shown (session state).
  static DateTime? _lastInterstitialShownAt;

  /// Show a non-rewarded interstitial ad between articles.
  ///
  /// Fire-and-forget: call when an article is opened, never before a
  /// coin grant (there is no link between ads and coins anymore).
  /// Never throws, never blocks the UI. If the ad isn't ready or fails,
  /// it silently does nothing.
  static Future<void> showInterstitialAd() async {
    if (!_initialized) return;
    try {
      await UnityAds.load(
        placementId: interstitialPlacementId,
        onComplete: (placementId) {},
        onFailed: (placementId, error, message) {},
      ).timeout(const Duration(seconds: 10), onTimeout: () {});
      final completer = Completer<void>();
      UnityAds.showVideoAd(
        placementId: interstitialPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {},
      );
    } catch (_) {
      // Silently ignore — ads are best-effort and never gate coins.
    }
  }

  /// Gated article interstitial (compliant model, v1.0.25).
  ///
  /// Call once per article open (fire-and-forget). Shows a non-rewarded
  /// interstitial only when BOTH gates pass:
  /// - at least [everyNthArticle] articles opened since the last show, and
  /// - at least [minGap] since the last show.
  /// Both values come from the remote-config earn rates, so the frequency
  /// can be tuned without a rebuild. The counter counts OPENS, not
  /// claims — the ad is never a condition for any coin grant.
  static Future<void> maybeShowArticleInterstitial({
    required int everyNthArticle,
    required Duration minGap,
  }) async {
    if (!adsEnabled || !_initialized) return;
    if (everyNthArticle <= 0) return;
    _articlesOpenedSinceAd++;
    if (_articlesOpenedSinceAd < everyNthArticle) return;
    final last = _lastInterstitialShownAt;
    if (last != null && DateTime.now().difference(last) < minGap) return;
    _articlesOpenedSinceAd = 0;
    _lastInterstitialShownAt = DateTime.now();
    await showInterstitialAd();
  }

  /// Show the App Open ad on cold start (dual-ad system).
  ///
  /// Call once after [init] completes, before showing home content.
  /// Never throws, never blocks startup — 8s max wait, then gives up.
  static Future<void> showAppOpenAd() async {
    if (!_initialized) return;
    try {
      await UnityAds.load(
        placementId: appOpenPlacementId,
        onComplete: (placementId) {},
        onFailed: (placementId, error, message) {},
      ).timeout(const Duration(seconds: 8), onTimeout: () {});
      final completer = Completer<void>();
      UnityAds.showVideoAd(
        placementId: appOpenPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
    } catch (_) {
      // Silently ignore — app continues to home.
    }
  }
}

/// Unity banner at the bottom of the shell, above the bottom navigation
/// bar (Doner-style mount). Renders nothing while the banner is loading
/// or if it fails to load, so the layout never leaves a permanent empty band.
class UnityBannerAdWidget extends StatefulWidget {
  const UnityBannerAdWidget({super.key});

  @override
  State<UnityBannerAdWidget> createState() => _UnityBannerAdWidgetState();
}

class _UnityBannerAdWidgetState extends State<UnityBannerAdWidget> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    if (!UnityAdsService.adsEnabled) return const SizedBox.shrink();
    // Single UnityBannerAd instance kept mounted (maintainState) so it
    // loads once and never reloads on rebuild; Visibility only controls
    // whether the loaded 50px banner takes space.
    return Visibility(
      visible: _loaded,
      maintainState: true,
      child: SizedBox(
        height: 50,
        child: Center(
          child: UnityBannerAd(
            placementId: UnityAdsService.bannerPlacementId,
            onLoad: (placementId) {
              if (mounted) setState(() => _loaded = true);
            },
            onClick: (placementId) {},
            onShown: (placementId) {},
            onFailed: (placementId, error, message) {
              if (mounted) setState(() => _loaded = false);
            },
          ),
        ),
      ),
    );
  }
}
