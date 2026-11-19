/// Rs display helpers for TJ Racing 3D cash earnings (v1.0.31).
///
/// User order (19 Nov 2026): EVERY cash earning shows its Rs value —
/// racing Level Coins AND article reading (5 coins/article) — "ta k
/// user ko pata ho k itny pesy ban gay hen". Ad Coins NEVER show Rs
/// (in-game only, never cash) — nothing in this file formats them.
///
/// The exact "Rs 0.10" form comes from the shared
/// [formatCoinsAsPkr] (validation.dart, integer math, always 2
/// decimals). This file only adds the short pill form ("Rs 12") and
/// the combined "10 coins = Rs 0.10" label used on the race result
/// screen. The rate always comes from config
/// (`games.tj_racing.level_coins.coins_per_pkr`, default 100);
/// article reading uses the same 100-coins-per-rupee rate.
///
/// Pure Dart, no Flutter imports (unit-testable).
library;

import '../../services/validation.dart' show formatCoinsAsPkr;

/// Short Rs form for pills ("1,240 • Rs 12"): whole rupees with no
/// decimals, "0.50" kept only when there is a paisa part.
/// [coinsPerPkr] comes from the racing remote config (default 100).
String formatRsShort(int coins, {int coinsPerPkr = 100}) {
  if (coinsPerPkr <= 0) return 'Rs 0';
  final negative = coins < 0;
  // Integer math only: total paisa at the configured rate.
  final totalPaisa = (coins.abs() * 100) ~/ coinsPerPkr;
  final rupees = totalPaisa ~/ 100;
  final paisa = totalPaisa % 100;
  final value = paisa == 0
      ? '$rupees'
      : '$rupees.${paisa.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}Rs $value';
}

/// Combined label for a cash earning: "10 coins = Rs 0.10".
/// Used on the race result screen and the article claim row.
/// [coinsPerPkr] comes from the racing remote config (default 100);
/// when it is not 100 the exact form still uses the shared 100-rate
/// formatter, so a non-100 rate falls back to the canonical rate
/// rather than printing a wrong value.
String coinsRsLabel(int coins, {int coinsPerPkr = 100}) {
  if (coinsPerPkr == 100) return '$coins coins = ${formatCoinsAsPkr(coins)}';
  // Non-default rate: show the short form at the configured rate so
  // the display never contradicts the config.
  return '$coins coins = ${formatRsShort(coins, coinsPerPkr: coinsPerPkr)}';
}
