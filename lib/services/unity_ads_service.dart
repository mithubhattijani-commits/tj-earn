import 'dart:async';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

/// Unity Ads rewarded video integration for TJ Earn.
///
/// - Game ID: 800417967 (Android, "TJ Earn" project)
/// - Rewarded placement: BP_Rewarded_Android (Active)
/// - Rewards are COINS (virtual currency), never cash — per Unity policy.
///   Coin grants happen server-side in the `claim-unity-reward` Edge
///   Function; this service only shows the ad and reports the outcome.
///
/// Test mode is ON for development. Flip [testMode] to false for
/// production builds.
class UnityAdsService {
  static const String gameId = '800417967';
  static const String rewardedPlacementId = 'BP_Rewarded_Android';

  /// Dual-ad system (Jaani, 2 Nov 2026): every app visit + every coin
  /// claim shows a Unity ad. Interstitial after claims, App Open on launch.
  /// Placement IDs follow the existing BP_ naming convention.
  static const String interstitialPlacementId = 'BP_Interstitial_Android';
  static const String appOpenPlacementId = 'BP_AppOpen_Android';

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

  /// MASTER AD KILL-SWITCH (Jaani, 2 Nov 2026): ALL Unity ads OFF.
  /// v1.0.7 delayed init didn't stop ANR — ads fully disabled until root
  /// cause is proven fixed. Set to true only on Jaani's explicit order.
  static const bool adsEnabled = false;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;

  /// Whether the SDK initialized successfully.
  static bool get isInitialized => _initialized;

  /// Whether init was attempted and failed (so the UI can explain why
  /// the Watch Ad button is unavailable).
  static bool get initFailed => _initFailed;

  /// Initialize the Unity Ads SDK. Safe to call once at app startup;
  /// subsequent calls are no-ops. Never throws.
  static Future<void> init() async {
    if (!adsEnabled) return;
    if (_initialized || _initFailed || _initStarted) return;
    _initStarted = true;
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
        onTimeout: () {},
      );
    } catch (_) {
      _initFailed = true;
    }
  }

  /// Load the rewarded video ad. Call before showing; also called
  /// automatically after each show so the next ad is ready.
  static Future<bool> loadRewardedAd() async {
    if (!_initialized) return false;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: rewardedPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Show the rewarded video ad.
  ///
  /// Returns [UnityAdResult.completed] when the user watched the full ad
  /// and earned the reward, [UnityAdResult.skipped] when they skipped
  /// early, [UnityAdResult.failed] on error.
  static Future<UnityAdResult> showRewardedAd() async {
    if (!_initialized) return UnityAdResult.failed;
    try {
      final completer = Completer<UnityAdResult>();
      UnityAds.showVideoAd(
        placementId: rewardedPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.skipped);
          }
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.completed);
          }
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.failed);
          }
        },
      );
      final result = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => UnityAdResult.failed,
      );
      // Preload the next ad in the background (never blocks the UI).
      unawaited(loadRewardedAd());
      return result;
    } catch (_) {
      return UnityAdResult.failed;
    }
  }

  /// Show a non-rewarded interstitial ad (dual-ad system).
  ///
  /// Fire-and-forget: call AFTER coins are granted, never before.
  /// Never throws, never blocks the UI. If the ad isn't ready or fails,
  /// it silently does nothing — the coins are already safe.
  static Future<void> showClaimInterstitial() async {
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
      // Silently ignore — ads are best-effort, coins already granted.
    }
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

/// Outcome of showing a rewarded ad.
enum UnityAdResult {
  /// User watched the full ad — credit the reward server-side.
  completed,

  /// User skipped before the end — no reward.
  skipped,

  /// Ad failed to load or show — no reward, show retry.
  failed,
}
