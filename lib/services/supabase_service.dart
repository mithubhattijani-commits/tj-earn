import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// All Supabase access for the app.
///
/// SECURITY: the app only ever *reads* the wallet. There is deliberately
/// no function here that writes coins to the ledger table. Coin grants
/// happen only inside Edge Functions (service role) after a verified
/// provider callback. A grep for ledger inserts across lib/ must return
/// zero code matches.
class SupabaseService {  static SupabaseClient get client => Supabase.instance.client;

  /// ROOT-CAUSE FIX (Jaani, 2 Nov 2026): every network call in this file
  /// is bounded by a hard timeout. A stalled network used to hang these
  /// futures forever — the UI showed infinite spinners and Android raised
  /// ANR. Now a stall surfaces as [TimeoutException] so every caller can
  /// render its error state instead.
  static Future<T> _guard<T>(Future<T> Function() call,
      {int seconds = 25}) {
    return call().timeout(
      Duration(seconds: seconds),
      onTimeout: () =>
          throw TimeoutException('Supabase request timed out'),
    );
  }

  /// Edge Function invoke with a hard timeout (see [_guard]).
  static Future<FunctionResponse> _invoke(
    String functionName, {
    Map<String, dynamic>? body,
    HttpMethod method = HttpMethod.post,
    Map<String, String>? queryParameters,
  }) {
    return _guard(
      () => client.functions.invoke(
        functionName,
        body: body,
        method: method,
        queryParameters: queryParameters,
      ),
    );
  }

  static Future<void> init() async {
    // 15s hard cap: main() never waits on the network before runApp.
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Supabase init timed out'),
    );
  }

  static User? get currentUser => client.auth.currentUser;

  static String? get userEmail => currentUser?.email;

  /// Balance from the server (SUM of the ledger, EXCLUDING Ad Coin
  /// rows — Ad Coins are in-game only and can never become cash, so
  /// `get-balance` never counts them). Never computed locally
  /// from anything the app could edit.
  static Future<int> getBalance() async {
    final res = await _invoke('get-balance');
    if (res.status != 200) {
      throw Exception('get-balance failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map && data['balance_coins'] is int) {
      return data['balance_coins'] as int;
    }
    throw Exception('get-balance returned an unexpected response');
  }

  /// Own ledger rows, newest first. RLS restricts this to the caller's rows.
  /// Bundled startup data (Jaani, 2 Nov 2026): ONE call returns balance,
  /// streak, onboarding progress, and the admin flag — replaces 4 separate
  /// calls that piled up on slow connections (ANR). Prefer
  /// [StartupBundleService.loadBundle] (cached) over calling this directly.
  static Future<Map<String, dynamic>> getStartupBundle() async {
    final res = await _invoke('get-startup-bundle');
    if (res.status != 200) {
      throw Exception('get-startup-bundle failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('get-startup-bundle returned an unexpected response');
  }

  static Future<List<Map<String, dynamic>>> getLedger() async {
    final user = currentUser;
    if (user == null) throw Exception('not signed in');
    final rows = await _guard(() => client
        .from('ledger')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(100));
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Own withdrawal requests, newest first.
  static Future<List<Map<String, dynamic>>> getWithdrawals() async {
    final user = currentUser;
    if (user == null) throw Exception('not signed in');
    final rows = await _guard(() => client
        .from('withdrawals')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(50));
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Submits a withdrawal request. The Edge Function re-validates the
  /// minimum, the balance and the pending-request cap, then stores the
  /// request as `pending`. The app never changes a request's status.
  static Future<void> requestWithdrawal({
    required int amountCoins,
    required String rail,
    required String accountNumber,
  }) async {
    final res = await _invoke(
      'request-withdrawal',
      body: {
        'amount_coins': amountCoins,
        'rail': rail,
        'account_number': accountNumber,
      },
    );
    if (res.status != 200) {
      final data = res.data;
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('request-withdrawal failed: $message');
    }
  }

  /// Referral info from the server: code, share link, totals and a
  /// privacy-conscious history (masked ids only). The code is auto-minted
  /// server-side on first call; the app never generates one itself.
  static Future<Map<String, dynamic>> getReferral() async {
    final res = await _invoke('get-referral');
    if (res.status != 200) {
      throw Exception('get-referral failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('get-referral returned an unexpected response');
  }

  /// Forwards a referral code the user typed. Every rule (self-referral,
  /// duplicates, rate limits) is enforced by the `apply-referral` Edge
  /// Function; the app only surfaces the server's verdict.
  static Future<Map<String, dynamic>> applyReferral(String code) async {
    final res = await _invoke(
      'apply-referral',
      body: {'code': code},
    );
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('apply-referral failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('apply-referral returned an unexpected response');
  }

  /// Claims pending referral bonuses (Jaani, 2 Nov 2026 — claim model).
  /// Pass empty list (or omit) to claim ALL pending. Returns
  /// {ok, claimed, coins}. Uses _guard timeout — never blocks UI.
  static Future<Map<String, dynamic>> claimReferralBonuses([
    List<String> ids = const [],
  ]) async {
    final res = await _invoke(
      'claim-referral-bonuses',
      body: {'ids': ids},
    );
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-referral-bonuses failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-referral-bonuses returned an unexpected response');
  }

  /// Latest published build from the public version-check function.
  /// Returns null when unconfigured or unreachable — the caller then skips
  /// the update check silently instead of showing a fake update.
  static Future<Map<String, dynamic>?> getLatestVersion() async {
    try {
      final res = await _invoke('version-check');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Claims the daily check-in streak.
  ///
  /// The `claim-streak` Edge Function tracks consecutive days and pays
  /// milestone bonuses at 7/14/21/30 days. Call this after a successful
  /// daily check-in. Returns current streak, milestone bonus (if any),
  /// and the next milestone.
  static Future<Map<String, dynamic>> claimStreak() async {
    final res = await _invoke('claim-streak');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      // 409 = already claimed today (not a hard error for the UI)
      if (res.status == 409 && data is Map<String, dynamic>) return data;
      throw Exception('claim-streak failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-streak returned an unexpected response');
  }


  /// Claims the daily check-in (compliant model, v1.0.25).
  ///
  /// The `claim-checkin` Edge Function awards the daily check-in coins
  /// (app_config `daily_checkin_coins`, approved 10/day) and tracks the
  /// streak. One claim per PKT day; 409 means already checked in today
  /// (returned as data, not thrown, so the UI can render the state).
  /// Returns the server's payload: `coins`, `already`, streak fields.
  /// The UI displays whatever `coins` the server returns — the server
  /// amount is authoritative.
  static Future<Map<String, dynamic>> claimCheckin() async {
    final res = await _invoke('claim-checkin');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      // 409 = already checked in today (not a hard error for the UI)
      if (res.status == 409 && data is Map<String, dynamic>) return data;
      throw Exception('claim-checkin failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-checkin returned an unexpected response');
  }

  /// Play & Earn wall URL (RapidoReach, v1.0.25).
  ///
  /// The signed wall URL comes from the `rapidoreach-wall-url` Edge
  /// Function, which builds the RapidoReach UID server-side from the
  /// caller's Supabase UUID (the App Key signs the UID, so it never
  /// enters the app). The app opens the returned URL in a WebView;
  /// completions credit through the `rapidoreach-postback` Edge
  /// Function into the server ledger — nothing here grants coins.
  /// Throws on any failure (function not deployed / not configured /
  /// offline); callers render their fail-soft state.
  static Future<String> getRapidoreachWallUrl() async {
    final res = await _invoke(
      'rapidoreach-wall-url',
      method: HttpMethod.get,
    );
    if (res.status != 200) {
      final data = res.data;
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('rapidoreach-wall-url failed: $message');
    }
    final data = res.data;
    if (data is Map &&
        data['wall_url'] is String &&
        (data['wall_url'] as String).isNotEmpty) {
      return data['wall_url'] as String;
    }
    throw Exception('rapidoreach-wall-url returned no URL');
  }

  /// Gets the user's current streak info (read-only).
  ///
  /// Returns current_streak, longest_streak, total_checkins.
  /// Returns nulls when the user has no streak yet.
  static Future<Map<String, dynamic>?> getStreak() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final row = await _guard(() => client
          .from('streaks')
          .select()
          .eq('user_id', user.id)
          .maybeSingle());
      if (row == null) return null;
      return (row as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Records an onboarding task completion.
  ///
  /// The `claim-onboarding` Edge Function validates the task key and pays
  /// the completion bonus when all tasks are done. Valid tasks: profile,
  /// checkin, quiz, spin, referral.
  static Future<Map<String, dynamic>> claimOnboarding(String task) async {
    final res = await _invoke(
      'claim-onboarding',
      body: {'task': task},
    );
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-onboarding failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-onboarding returned an unexpected response');
  }

  /// Gets the user's onboarding progress (read-only).
  ///
  /// Returns the list of completed task keys.
  static Future<List<String>> getOnboardingProgress() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final rows = await _guard(() => client
          .from('onboarding_tasks')
          .select('task_key')
          .eq('user_id', user.id));
      return (rows as List)
          .map((r) => (r as Map)['task_key'] as String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Checks and pays referral milestone tier bonuses.
  ///
  /// The `check-referral-milestone` Edge Function counts approved referrals
  /// and pays tier bonuses at 5/10/25. Idempotent — safe to call often.
  static Future<Map<String, dynamic>> checkReferralMilestone() async {
    final res = await _invoke('check-referral-milestone');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('check-referral-milestone failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('check-referral-milestone returned an unexpected response');
  }

  /// Gets the weekly leaderboard (top 20 earners, anonymized).
  ///
  /// The `get-leaderboard` Edge Function returns masked entries plus the
  /// caller's own rank. Read-only.
  static Future<Map<String, dynamic>> getLeaderboard() async {
    final res = await _invoke('get-leaderboard');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('get-leaderboard failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('get-leaderboard returned an unexpected response');
  }

  /// Registers the device for anti-fraud tracking.
  ///
  /// The `register-device` Edge Function stores a device hash. Call once
  /// per login. Returns whether the device is flagged (>3 users).
  static Future<Map<String, dynamic>?> registerDevice(
      String deviceHash, String deviceModel) async {
    try {
      final res = await _invoke(
        'register-device',
        body: {'device_hash': deviceHash, 'device_model': deviceModel},
      );
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// ADMIN — referrals queue (read-only). Server enforces the admin gate;
  /// a 403 (forbidden) or 503 (admin not configured) surfaces as
  /// [AdminAccessDenied] so the UI can show the "admin access required"
  /// empty state instead of retrying.
  static Future<Map<String, dynamic>> listReferrals({
    String status = 'eligible',
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _invoke(
      'list-referrals',
      method: HttpMethod.get,
      queryParameters: {
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _adminResult(res, 'list-referrals');
  }

  /// ADMIN — referral aggregate stats (read-only). See [listReferrals] for
  /// the authorization behaviour.
  static Future<Map<String, dynamic>> referralStats() async {
    final res = await _invoke(
      'referral-stats',
      method: HttpMethod.get,
    );
    return _adminResult(res, 'referral-stats');
  }

  /// ADMIN — paginated ledger view (read-only). Optional `userId` / `type`
  /// filters. See [listReferrals] for the authorization behaviour.
  static Future<Map<String, dynamic>> listLedger({
    int limit = 50,
    int offset = 0,
    String? userId,
    String? type,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (userId != null && userId.isNotEmpty) params['user_id'] = userId;
    if (type != null && type.isNotEmpty) params['type'] = type;
    final res = await _invoke(
      'list-ledger',
      method: HttpMethod.get,
      queryParameters: params,
    );
    return _adminResult(res, 'list-ledger');
  }

  /// ADMIN — approves or rejects a referral via the existing
  /// `review-referral` Edge Function. Server-side idempotent: replaying an
  /// approval can never double-credit the referrer.
  static Future<Map<String, dynamic>> reviewReferral({
    required String referralId,
    required String action,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'referral_id': referralId,
      'action': action,
    };
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    final res = await _invoke('review-referral', body: body);
    return _adminResult(res, 'review-referral');
  }

  /// Unpacks an admin function response: 200 -> the payload map;
  /// 403/503 -> [AdminAccessDenied]; anything else -> a generic Exception
  /// carrying the server's error string when present.
  static Map<String, dynamic> _adminResult(
      FunctionResponse res, String name) {
    if (res.status == 403 || res.status == 503) {
      throw AdminAccessDenied(res.status);
    }
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('$name failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('$name returned an unexpected response');
  }

  /// Display fallback for the daily reading cap (compliant model,
  /// v1.0.25: 200 unique articles/day). The SERVER is authoritative —
  /// `submit-reading` enforces app_config `read_article_daily_cap`.
  /// This constant is only used when the server does not report a
  /// remaining count, so the UI never shows a stale 30/day or 5/day.
  static const int _readDailyCap = 200;

  /// Article-reading reward (Jaani, 3 Nov 2026): website <-> app integration.
  ///
  /// Compliant model (v1.0.25): coins come ONLY from reading (5 coins per
  /// UNIQUE article, cap 200/day — server-enforced in `submit-reading`
  /// via app_config `read_article_coins` / `read_article_daily_cap`),
  /// daily check-in and referrals. There is no rewarded-ad coin path
  /// anymore: `claim-unity-reward` and the Unity rewarded placement are
  /// removed (Unity ticket #00945584 — coins-to-cash via rewarded ads is
  /// prohibited). The server enforces the cap and the minimum read time
  /// (app_config `read_min_dwell_seconds`, 30s) — the client only
  /// renders state and mirrors the same 30s countdown.
  ///
  /// [getReadingRemaining] returns how many reading claims are left today
  /// (0-200). [submitReading] claims +5 coins for [articleId]; throws on
  /// 429 (cap reached) or other failures. Re-reading an article the user
  /// already claimed pays 0 — the server credits one article once per user.

  static Future<int> getReadingRemaining() async {
    final res = await _invoke('get-reading');
    if (res.status != 200) {
      throw Exception('get-reading failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map) {
      // Server returns remaining count; be lenient about the key name.
      for (final key in ['remaining', 'remaining_today', 'left']) {
        if (data[key] is int) return data[key] as int;
      }
      // Fallback: derive from claimed count if provided.
      if (data['claimed_today'] is int) {
        final claimed = data['claimed_today'] as int;
        final remaining = _readDailyCap - claimed;
        return remaining < 0 ? 0 : (remaining > _readDailyCap ? _readDailyCap : remaining);
      }
    }
    return _readDailyCap; // Unknown — let the claim attempt surface the real state.
  }

  static Future<void> submitReading(String articleId) async {
    final res = await _invoke('submit-reading', body: {
      'article_id': articleId,
    });
    if (res.status == 429) {
      throw Exception('reading cap reached (429)');
    }
    if (res.status != 200) {
      final data = res.data;
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('submit-reading failed: $message');
    }
  }

  /// Arrow Puzzle level reward (v1.0.27).
  ///
  /// Coins come ONLY from completing a level, never from an ad. The
  /// server (`claim-game-level` Edge Function) is authoritative: it
  /// credits `game_level_coins` once per level per user (idempotency
  /// key `game-level-<user>-<level>`, or `...-daily-<YYYY-MM-DD>` for
  /// the Daily Challenge) and enforces the daily game-coin cap
  /// (`game_level_daily_cap`). The client only renders the result.
  /// Returns the function payload: `{ok, coins, already, remaining?}`.
  /// Throws on 429 (daily cap reached) or other failures. A 409
  /// (already claimed) is returned as data, not thrown — the win
  /// dialog renders it as state.
  static Future<Map<String, dynamic>> claimGameLevel(
    int level, {
    required bool dailyChallenge,
    required int moves,
    required int heartsLost,
  }) async {
    final res = await _invoke('claim-game-level', body: {
      'level': level,
      'daily_challenge': dailyChallenge,
      'moves': moves,
      'hearts_lost': heartsLost,
    });
    if (res.status == 429) {
      throw Exception('game daily cap reached (429)');
    }
    final data = res.data;
    if (res.status == 409 && data is Map<String, dynamic>) {
      return data;
    }
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-game-level failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-game-level returned an unexpected response');
  }

  /// Game coins earned today (own bucket, separate from reading).
  /// Served by `claim-game-level` over GET — no claim is made.
  static Future<int> getGameCoinsToday() async {
    final res = await _invoke(
      'claim-game-level',
      method: HttpMethod.get,
    );
    if (res.status != 200) {
      throw Exception('get game coins failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map && data['coins_today'] is int) {
      return data['coins_today'] as int;
    }
    return 0;
  }

  /// Arrow Puzzle Ad Coin claim (Watch Ads, v1.0.27).
  ///
  /// Ad Coins are earned ONLY by watching a rewarded ad, and only
  /// through this server claim: the caller must first complete a
  /// rewarded ad (`GameRewardAdService.tryGrantAdCoins` answering
  /// `granted`) and then claim with the idempotency key generated
  /// for that ad view. The server (`claim-ad-reward` Edge Function)
  /// is authoritative: it credits `game_ad_coins_per_ad` (default
  /// 10) and enforces the daily cap (`game_ad_coins_daily_cap`,
  /// default 100, server-side sum of today's `game_ad_reward`
  /// rows). The client never credits Ad Coins itself.
  /// Returns the function payload: `{ok, ad_coins, already,
  /// ad_coins_today, ad_coins_balance, remaining?}`. Throws on 429
  /// (daily cap reached) or other failures. A 409 (already claimed
  /// for this key) is returned as data, not thrown.
  static Future<Map<String, dynamic>> claimAdReward({
    required String idempotencyKey,
  }) async {
    final res = await _invoke('claim-ad-reward', body: {
      'idempotency_key': idempotencyKey,
    });
    if (res.status == 429) {
      throw Exception('ad daily cap reached (429)');
    }
    final data = res.data;
    if (res.status == 409 && data is Map<String, dynamic>) {
      return data;
    }
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-ad-reward failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-ad-reward returned an unexpected response');
  }

  /// Ad Coin balance + today's earnings (own bucket, separate from
  /// the cash balance). Served by `claim-ad-reward` over GET — no
  /// claim is made. Returns `{ad_coins_balance, ad_coins_today,
  /// remaining, cap}`.
  static Future<Map<String, dynamic>> getAdCoins() async {
    final res = await _invoke(
      'claim-ad-reward',
      method: HttpMethod.get,
    );
    if (res.status != 200) {
      throw Exception('get ad coins failed: ${res.status}');
    }
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return const <String, dynamic>{};
  }

  /// Unique-per-attempt idempotency key for coin spends and Ad Coin
  /// claims. A retry after a partial failure reuses the SAME key, so
  /// the server can answer "already done" instead of crediting or
  /// charging twice.
  static String newIdempotencyKey(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$prefix-$stamp-${sha256.convert(bytes).toString().substring(0, 16)}';
  }

  /// Arrow Puzzle coin spend (hints / power / extra life).
  ///
  /// The server (`spend-game-item` Edge Function) checks the balance
  /// against the configured price and inserts a negative ledger row.
  /// The client never deducts coins itself. Each attempt carries a
  /// fresh client-generated idempotency key, so a retry after a
  /// partial failure can never double-charge. Returns the payload:
  /// `{ok:true, new_balance, new_ad_balance}`. Throws when the
  /// balance is too low (402) or the call fails.
  ///
  /// [currency] selects the bucket (see `ad_coins.dart` — the two
  /// currencies never mix): `'level_coins'` (default) spends Level
  /// Coins from the cash balance; `'ad_coins'` spends Ad Coins from
  /// the in-game-only Ad Coin balance. Ad Coins can never pay for
  /// anything outside the game and can never become cash.
  static Future<Map<String, dynamic>> spendGameItem({
    required String item,
    required int level,
    String currency = 'level_coins',
  }) async {
    final res = await _invoke('spend-game-item', body: {
      'item': item,
      'level': level,
      'currency': currency,
      'idempotency_key': newIdempotencyKey('spend'),
    });
    final data = res.data;
    if (res.status == 402) {
      throw Exception('not enough coins');
    }
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('spend-game-item failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('spend-game-item returned an unexpected response');
  }
}

/// Thrown when an admin Edge Function denies the caller: 403 means the
/// signed-in email is not an admin; 503 means no admin is configured.
/// The server is the enforcer — the client only renders the empty state.
class AdminAccessDenied implements Exception {
  final int status;
  const AdminAccessDenied(this.status);

  @override
  String toString() => 'admin access denied ($status)';
}
