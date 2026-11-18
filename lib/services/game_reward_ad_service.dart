/// Ad-gated Ad Coin grants for the Arrow Puzzle (Watch Ads option,
/// user-approved 18 Nov 2026).
///
/// TWO CURRENCIES (see `games/arrow_puzzle/ad_coins.dart`): watching
/// a rewarded ad earns Ad Coins — spendable ONLY in-game (hints /
/// power / extra life), NEVER cash, NEVER convertible to Level
/// Coins. Cash comes ONLY from Level Coins (level completion).
///
/// SAFE DEFAULT (Unity ticket 00946156, Open): the compliant model
/// removed the rewarded placement (`BP_Rewarded_Android`) entirely,
/// so there is NO rewarded ad to show in this build. This service is
/// the single extension point: it answers `disabled` while the
/// remote-config flag is off and `unavailable` while no rewarded
/// placement exists. The UI hides the Watch Ad button entirely while
/// the flag is off, and shows "ad not available" otherwise.
///
/// The full grant path (once Unity approves and a placement is
/// wired): rewarded-ad completion callback -> this service answers
/// `granted` -> the caller claims the Ad Coins from the server
/// (`claim-ad-reward` Edge Function, idempotency key per ad view).
/// The client NEVER credits Ad Coins itself — the server claim is
/// the only credit, and it enforces the daily cap.
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
  unavailable,

  /// The ad failed or was skipped before completion.
  failed,
}

class GameRewardAdService {
  GameRewardAdService._();

  /// Attempts one rewarded-ad view for Ad Coins. Returns `disabled`
  /// when the flag is off (the UI must not have offered the button),
  /// `unavailable` in this build (no rewarded placement exists yet).
  /// A real `granted` is only possible after a rewarded placement
  /// (`BP_Rewarded_Android`) is deliberately wired back in AFTER
  /// Unity approves on ticket 00946156.
  static Future<AdGrantResult> tryGrantAdCoins({
    required bool adsEnabled,
  }) async {
    if (!adsEnabled) return AdGrantResult.disabled;
    // Intentionally unimplemented: no rewarded placement exists in
    // this build (compliant model, Unity ticket #00945584). Wiring one
    // requires Unity's approval on ticket 00946156 first.
    return AdGrantResult.unavailable;
  }
}
