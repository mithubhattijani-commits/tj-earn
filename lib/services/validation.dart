// Pure, unit-tested business rules for TJ Earn.
//
// These rules are mirrored in the Supabase Edge Functions. The app never
// enforces them alone: the server re-validates every request. Keeping the
// same logic here gives instant, honest feedback in the UI.

/// Coins per whole rupee. 1 coin = Rs 0.01, so 100 coins = Rs 1.
const int coinsPerPkr = 100;

/// Minimum withdrawal: 10,000 coins = Rs 100.
///
/// Changed 11 Nov 2026 (Jaani: "Ye 100 ropay kardo") — the deployed
/// `request-withdrawal` Edge Function and app_config
/// `min_withdrawal_coins` were set to 10000 then; this constant is kept
/// in sync so the app's instant validation matches the server.
const int minWithdrawalCoins = 10000;

/// Maximum number of pending withdrawal requests a user may hold at once.
const int maxPendingWithdrawals = 2;

/// Formats a coin amount as rupees, using integer math only (no floats).
/// 10000 -> "Rs 100.00", 10050 -> "Rs 100.50", 5 -> "Rs 0.05".
String formatCoinsAsPkr(int coins) {
  final negative = coins < 0;
  final abs = coins.abs();
  final rupees = abs ~/ coinsPerPkr;
  final paisa = abs % coinsPerPkr;
  return '${negative ? '-' : ''}Rs $rupees.${paisa.toString().padLeft(2, '0')}';
}

/// Converts whole rupees to coins. 100 -> 10000.
int pkrToCoins(int wholePkr) => wholePkr * coinsPerPkr;

/// Builds the referral share link for a code. Pure function, unit-tested.
/// The domain is the production website; never a placeholder.
String buildReferralLink(String code) =>
    'https://nigraantv.xyz/earn/?ref=${code.trim().toUpperCase()}';

/// True when a referral code matches the server format: 8 chars from the
/// unambiguous alphabet (no 0/O, 1/I/L). Mirrors the Edge Function check —
/// the alphabet is written out explicitly because A-Z would wrongly allow
/// the look-alikes O, I and L.
bool isValidReferralCode(String code) => RegExp(
      r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$',
    ).hasMatch(code.trim().toUpperCase());

/// Validation failure keys (localised in the UI). Null means valid.
String? validateWithdrawal({
  required int amountCoins,
  required int balanceCoins,
  required int pendingCount,
}) {
  if (amountCoins <= 0) return 'amount_positive';
  if (amountCoins < minWithdrawalCoins) return 'amount_min';
  if (amountCoins % coinsPerPkr != 0) return 'amount_whole_rupees';
  if (amountCoins > balanceCoins) return 'amount_exceeds_balance';
  if (pendingCount >= maxPendingWithdrawals) return 'too_many_pending';
  return null;
}

/// True when the server reports a strictly newer build.
bool isNewerVersion(int latestCode, int currentCode) =>
    latestCode > currentCode;

/// Masks an account number for display/storage: keeps only the last 4 digits.
String maskAccount(String account) {
  final digits = account.replaceAll(RegExp(r'\s'), '');
  if (digits.length <= 4) return '****';
  return '****${digits.substring(digits.length - 4)}';
}

/// In-memory replay guard mirroring the ledger's UNIQUE idempotency_key.
/// Returns true the first time a key is seen, false on any replay.
class IdempotencyGuard {
  final Set<String> _seen = <String>{};

  bool claim(String key) => _seen.add(key);
}
