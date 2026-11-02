import 'dart:async';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

/// Unity Ads integration for TJ Earn.
///
/// - Game ID: 800417967 (Android, "TJ Earn" project)
/// - Rewarded placement: BP_Rewarded_Android (Active) — user-initiated
///   Watch Ad screen. Coins credited server-side by `claim-unity-reward`.
/// - Interstitial placement: BP_Interstitial_Android — shown fire-and-forget
///   after every coin claim (streak, spin, onboarding). Never blocks coins.
/// - App Open placement: BP_AppOpen_Android — shown once per cold start,
///   best-effort with timeout, never blocks the app.
///
/// Rewards are COINS (virtual currency), never cash — per Unity policy.
/// Coin grants happen server-side in Edge Functions; this service only
/// shows ads and reports outcomes.
///
/// NOTE (Jaani, 2 Nov 2026): the Interstitial and App Open placements must
/// exist in the Unity dashboard for the TJ Earn project (Game ID 800417967).
/// Create them as:
///   - BP_Interstitial_Android (Interstitial Video)
///   - BP_AppOpen_Android (App Open)
/// Until they exist, those calls fail silently and the app works normally.
///
/// Test mode is OFF for production builds.
class UnityAdsService {
  static const String gameId = '800417967';
  static const String rewardedPlacementId = 'BP_Rewarded_Android';
  static const String interstitialPlacementId = 'BP_Interstitial_Android';
  static const String appOpenPlacementId = 'BP_AppOpen_Android';

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;
  static bool _appOpenShownThisLaunch = false;

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
    // Preload the interstitial in the background so it's ready when
    // the first coin claim completes. Never blocks.
    if (_initialized) {
      unawaited(loadInterstitialAd());
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

  // ------------------------------------------------------------------
  // Interstitial (non-rewarded) — fire-and-forget after coin claims.
  // ------------------------------------------------------------------

  /// Load the interstitial ad. Best-effort; returns false on any failure.
  static Future<bool> loadInterstitialAd() async {
    if (!_initialized) return false;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: interstitialPlacementId,
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

  /// Show an interstitial ad. Fire-and-forget: never throws, never blocks
  /// the caller. Call AFTER coins are granted — the ad must never gate
  /// or delay a reward. If the ad isn't ready, this is a silent no-op.
  ///
  /// Usage: `unawaited(UnityAdsService.showInterstitialAd());`
  static Future<void> showInterstitialAd() async {
    if (!_initialized) return;
    try {
      final loaded = await loadInterstitialAd();
      if (!loaded) return;
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
      // Silent — ads are best-effort.
    }
    // Preload the next one for the following claim.
    unawaited(loadInterstitialAd());
  }

  // ------------------------------------------------------------------
  // App Open — shown once per cold start, best-effort.
  // ------------------------------------------------------------------

  /// Show the App Open ad once per app launch. Fire-and-forget: never
  /// throws, gives up after [timeout], and never blocks app startup.
  /// Safe to call multiple times — only the first call per launch shows.
  ///
  /// Usage: `unawaited(UnityAdsService.showAppOpenAd());` after init.
  static Future<void> showAppOpenAd({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_appOpenShownThisLaunch) return;
    _appOpenShownThisLaunch = true;
    if (!_initialized) return;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: appOpenPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      final loaded = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      if (!loaded) return;
      final showCompleter = Completer<void>();
      UnityAds.showVideoAd(
        placementId: appOpenPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!showCompleter.isCompleted) showCompleter.complete();
        },
        onComplete: (placementId) {
          if (!showCompleter.isCompleted) showCompleter.complete();
        },
        onFailed: (placementId, error, message) {
          if (!showCompleter.isCompleted) showCompleter.complete();
        },
      );
      await showCompleter.future.timeout(timeout, onTimeout: () {});
    } catch (_) {
      // Silent — ads are best-effort.
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
