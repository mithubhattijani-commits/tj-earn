import 'dart:async';
import 'package:flutter/material.dart';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import 'remote_config_service.dart';

/// Unity Ads rewarded video integration for TJ Earn.
///
/// - Game ID: 800417967 (Android, "TJ Earn" project)
/// - Rewarded placement: BP_Rewarded_Android (Active)
/// - Banner placement: BP_Banner_Android (Active)
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
  static const String bannerPlacementId = 'BP_Banner_Android';

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

  /// ADS BACK ON (Jaani, 2 Nov 2026): the v1.0.9 diagnostic (ads fully
  /// off) proved the ANR is NOT ad-related — kill-switch lifted on his
  /// explicit order ("ads phir ON kar dein ge").
  ///
  /// MASTER SWITCH (14 Nov 2026, Doner pattern): read live from the
  /// website admin panel (tj-earn.json "ads.ads_enabled", default
  /// true = fail-open) — the user turns ALL Unity ads off from the
  /// panel with no new build. The per-zone switches gate individual
  /// screens on top of this. Before the first config fetch the
  /// bundled default is all-true, so ads behave exactly as today.
  static bool get adsEnabled =>
      RemoteConfigService.instance.config.ads.adsEnabled;

  /// Rewarded-video kill-switch (tj-earn.json
  /// "ads.rewarded_enabled", default true = fail-open). The rewarded
  /// flow itself is unchanged and stays opt-in only; when this is
  /// false the Watch Ad button's load simply fails, as if no ad
  /// was available.
  static bool get rewardedEnabled =>
      RemoteConfigService.instance.config.ads.rewardedEnabled;

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

  /// Load the rewarded video ad. Call before showing; also called
  /// automatically after each show so the next ad is ready.
  static Future<bool> loadRewardedAd() async {
    if (!_initialized || !rewardedEnabled) return false;
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
    if (!_initialized || !rewardedEnabled) return UnityAdResult.failed;
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

/// A Unity banner slot gated by one per-zone remote-config switch.
///
/// The [zone] selector reads the zone from the current remote config
/// (e.g. `(ads) => ads.bannerHome`). When the zone is off — or the
/// master switch is off — the slot renders nothing (zero height);
/// when it is on, the inner [UnityBannerAdWidget] renders the banner
/// and itself shrinks to nothing while loading or on failure.
/// Rebuilds automatically when the remote config refreshes (60s poll).
/// Place it in a quiet bottom slot — never over content, never
/// blocking a button. Doner pattern, 14 Nov 2026.
class ZonedUnityBanner extends StatelessWidget {
  const ZonedUnityBanner({super.key, required this.zone});

  final bool Function(AdsConfig) zone;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (context, config, _) {
        if (!zone(config.ads)) return const SizedBox.shrink();
        return const UnityBannerAdWidget();
      },
    );
  }
}
