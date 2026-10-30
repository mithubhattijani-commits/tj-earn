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

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

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
