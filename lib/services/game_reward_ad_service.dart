import 'unity_ads_service.dart';

/// Ad-gated Ad Coin grants for the Arrow Puzzle (Watch Ads option,
/// user-approved 18 Nov 2026).
///
/// TWO CURRENCIES (see `games/arrow_puzzle/ad_coins.dart`): watching
/// a rewarded ad earns Ad Coins — spendable ONLY in-game (hints /
/// power / extra life), NEVER cash, NEVER convertible to Level
/// Coins. Cash comes ONLY from Level Coins (level completion).
///
/// REWARDED PLACEMENT (v1.0.27, user order 18 Nov ~14:54 — flag ON
/// without waiting for Unity ticket 00946156, suspension risk
/// disclosed and accepted by the user): a completed rewarded ad view
/// (`BP_Rewarded_Android`, [UnityAdsService.showRewardedAd]) is the
/// single trigger for the server claim. The client NEVER credits Ad
/// Coins itself — the server claim is the only credit, and it
/// enforces the daily cap. If the dashboard placement does not exist
/// or the ad fails/skips, the service answers `failed` and the UI
/// shows "ad not available" — no coins are ever granted without a
/// completed ad view.
///
/// The remote-config flag `games.arrow_puzzle.ads_for_rewards_enabled`
/// (default false) is the first gate; this service is the second.
/// Both must pass before any ad is ever shown for a reward.
enum AdGrantResult {
  /// The ad completed; the caller may now claim the Ad Coins.
  granted,

  /// The flag is off — the Watch Ad option is not offered at all.
  disabled,

  /// The flag is on but no rewarded ad is available in this build.
  /// Kept for callers that distinguish "no placement" from a failed
  /// show; the current implementation answers [failed] when the
  /// placement show itself fails.
  unavailable,

  /// The ad failed or was skipped before completion.
  failed,
}

class GameRewardAdService {
  GameRewardAdService._();

  /// Attempts one rewarded-ad view for Ad Coins. Returns `disabled`
  /// when the flag is off (the UI must not have offered the button),
  /// `granted` only when the rewarded ad played to completion, and
  /// `failed` when it was skipped, failed to load/show, or the
  /// dashboard placement does not exist.
  ///
  /// [showRewardedAd] is an injection point for tests; production
  /// uses [UnityAdsService.showRewardedAd].
  static Future<AdGrantResult> tryGrantAdCoins({
    required bool adsEnabled,
    Future<bool> Function()? showRewardedAd,
  }) async {
    if (!adsEnabled) return AdGrantResult.disabled;
    final show = showRewardedAd ?? UnityAdsService.showRewardedAd;
    final completed = await show();
    return completed ? AdGrantResult.granted : AdGrantResult.failed;
  }
}
