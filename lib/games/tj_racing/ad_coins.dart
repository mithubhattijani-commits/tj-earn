/// Ad Coins — the in-game-only currency of TJ Racing 3D
/// (Watch Ads + car/power-up shop, v1.0.31).
///
/// TWO CURRENCIES, NEVER MIXED — this separation is the whole point:
///
/// | | Level Coins | Ad Coins |
/// |---|---|---|
/// | Earned by | winning / placing in a race (10 win, 5 second, 200/day cap) | watching a rewarded ad (10/ad, 100/day cap) |
/// | Spendable on | NOTHING in-game — never spent | cars + power-ups ONLY |
/// | Withdrawable as cash | YES (min 10,000 = Rs 100) | NEVER |
/// | Converts to Level Coins | — | NEVER — no conversion path exists anywhere |
///
/// The server enforces this with separate ledger types. The cash
/// balance (`get-balance`, `request-withdrawal`, and the Level-Coin
/// path of `spend-game-item`) sums the ledger EXCLUDING the Ad Coin
/// types, so Ad Coins can never inflate a cash balance or be
/// withdrawn. The Ad Coin balance is the sum of `game_ad_reward`
/// rows minus `game_ad_spend` rows — nothing else touches it.
/// (Same ledger bucket as the removed Arrow Puzzle — the server
/// functions `claim-ad-reward` / `spend-game-item` are unchanged.)
///
/// Pure Dart, no Flutter imports (unit-testable). The grant math is
/// deliberately here, not in a widget, so the cap rules can be
/// tested without a device.
library;

/// Ledger type of an Ad Coin credit (one watched ad).
const String adRewardLedgerType = 'game_ad_reward';

/// Ledger type of an Ad Coin debit (a car / power-up bought with
/// Ad Coins).
const String adSpendLedgerType = 'game_ad_spend';

/// Ledger types that belong to the Ad Coin bucket.
const List<String> adCoinLedgerTypes = [
  adRewardLedgerType,
  adSpendLedgerType,
];

/// Ad Coin grant rules (defaults match the remote config).
class AdCoins {
  AdCoins._();

  /// Ad Coins granted per fully-watched rewarded ad.
  static const int defaultPerAd = 10;

  /// Max Ad Coins earnable per day (UTC day bucket, server-side).
  static const int defaultDailyCap = 100;

  /// How many Ad Coins the next watched ad may grant, given how many
  /// were already earned today. Partial grant at the cap edge
  /// (e.g. 95 earned, cap 100 -> 5); 0 once the cap is reached.
  /// Never negative, never above [perAd].
  static int grantable({
    required int earnedToday,
    required int perAd,
    required int dailyCap,
  }) {
    if (perAd <= 0 || dailyCap <= 0) return 0;
    final remaining = dailyCap - earnedToday;
    if (remaining <= 0) return 0;
    return remaining < perAd ? remaining : perAd;
  }

  /// There is NO conversion from Ad Coins to Level Coins or cash.
  /// This method exists only so the rule is stated in code and
  /// testable: any conversion attempt is a programming error.
  /// Ad Coins are spent only through `spend-race-item` with
  /// currency 'ad_coins', and only on cars / power-ups.
  static Never toLevelCoins(int adCoins) {
    throw UnsupportedError(
      'Ad Coins can never convert to Level Coins or cash '
      '(tried to convert $adCoins Ad Coins).',
    );
  }
}
