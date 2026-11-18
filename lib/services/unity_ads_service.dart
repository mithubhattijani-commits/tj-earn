import 'dart:async';
import 'package:flutter/material.dart';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

/// Unity Ads integration for TJ Earn (compliant model, v1.0.25;
/// rewarded Ad Coins wired back in v1.0.27, see below).
///
/// COMPLIANT MODEL (17 Nov 2026, Unity ticket #00945584): coins-to-cash
/// via rewarded ads is PROHIBITED on self-serve Unity Ads — rewards for
/// watching ads must be in-app virtual only, never cash. TJ Earn pays
/// cash for READING, so NO cash coin may ever come from any ad view.
/// The v1.0.25 build therefore removed the rewarded placement
/// entirely. v1.0.27 wires it back ONLY for Ad Coins (Arrow Puzzle
/// Watch Ads, user order 18 Nov ~14:54 — flag ON without waiting for
/// Unity ticket 00946156, suspension risk disclosed and accepted by
/// the user): Ad Coins are spendable ONLY in-game (hints / power /
/// extra life), NEVER cash, NEVER convertible to Level Coins. The
/// server claim (`claim-ad-reward`) is the only credit and enforces
/// the daily cap; the client never credits Ad Coins itself.
///
/// What remains (all earning only):
/// - Game ID: 800417967 (Android, "TJ Earn" project)
/// - Banner placement: BP_Banner_Android (Active) — passive bottom slot.
/// - Interstitial placement: BP_Interstitial_Android (Active) — shown
///   between articles via [maybeShowArticleInterstitial], gated by the
///   remote-config earn rates (every Nth article, min gap). Never
///   rewarded, never tied to any coin grant.
/// - App Open placement: BP_AppOpen_Android (Active) — cold start only.
/// - Rewarded placement: BP_Rewarded_Android — Arrow Puzzle Watch Ads
///   ONLY (see [showRewardedAd]). The dashboard placement must exist
///   for game 800417967; if it does not, the show fails and the UI
///   reports "ad not available" — no coins are ever granted without a
///   completed ad view.

/// Test mode is ON for development. Flip [testMode] to false for
/// production builds.
class UnityAdsService {
  static const String gameId = '800417967';

  /// Dual-ad system (Jaani, 2 Nov 2026): every app visit + every coin
  /// claim shows a Unity ad. Interstitial after claims, App Open on launch.
  /// Placement IDs follow the existing BP_ naming convention.
  ///
  /// Rewarded placement (v1.0.27, user order 18 Nov ~14:54): wired
  /// back ONLY for Arrow Puzzle Ad Coins — in-game virtual currency,
  /// never cash, never convertible (see the class doc). If the
  /// dashboard placement does not exist, [showRewardedAd] fails
  /// closed and no grant happens.
  static const String interstitialPlacementId = 'BP_Interstitial_Android';
  static const String appOpenPlacementId = 'BP_AppOpen_Android';
  static const String bannerPlacementId = 'BP_Banner_Android';
  static const String rewardedPlacementId = 'BP_Rewarded_Android';

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

  /// Show a rewarded ad for Arrow Puzzle Ad Coins (v1.0.27).
  ///
  /// Returns true ONLY when the ad played to completion — that is the
  /// single signal the caller uses to claim Ad Coins from the server
  /// (the client never credits Ad Coins itself). Returns false when
  /// the ad was skipped, failed to load/show, timed out, or the SDK
  /// is not initialized — including when the dashboard placement
  /// `BP_Rewarded_Android` does not exist for this game. Never
  /// throws, never blocks the UI beyond the ad itself (2 min max).
  static Future<bool> showRewardedAd() async {
    if (!_initialized) return false;
    try {
      var loaded = false;
      await UnityAds.load(
        placementId: rewardedPlacementId,
        onComplete: (placementId) {
          loaded = true;
        },
        onFailed: (placementId, error, message) {},
      ).timeout(const Duration(seconds: 10), onTimeout: () {});
      if (!loaded) return false;
      final completer = Completer<bool>();
      UnityAds.showVideoAd(
        placementId: rewardedPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
    } catch (_) {
      // Fail closed: no completed ad, no grant.
      return false;
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

  /// Levels completed since the last level interstitial (session counter).
  static int _levelsCompletedSinceAd = 0;

  /// Gated Arrow Puzzle interstitial (v1.0.27) — mirror of
  /// [maybeShowArticleInterstitial].
  ///
  /// Call once per completed level (fire-and-forget), AFTER the win
  /// dialog is dismissed. Same non-rewarded placement, same gates:
  /// every Nth completed level + min gap since the last interstitial
  /// of either kind (the gap is shared, so articles and levels never
  /// stack ads). The ad is never a condition for the coin grant.
  static Future<void> maybeShowLevelInterstitial({
    required int everyNthLevel,
    required Duration minGap,
  }) async {
    if (!adsEnabled || !_initialized) return;
    if (everyNthLevel <= 0) return;
    _levelsCompletedSinceAd++;
    if (_levelsCompletedSinceAd < everyNthLevel) return;
    final last = _lastInterstitialShownAt;
    if (last != null && DateTime.now().difference(last) < minGap) return;
    _levelsCompletedSinceAd = 0;
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
