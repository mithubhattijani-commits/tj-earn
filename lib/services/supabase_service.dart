import 'dart:async';

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
      () => _invoke(
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

  /// Balance from the server (SUM of the ledger). Never computed locally
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

  /// Claims coins for a completed Unity rewarded video ad.
  ///
  /// The `claim-unity-reward` Edge Function verifies the caller's JWT,
  /// enforces the daily cap and the 30-second anti-spam gap, then credits
  /// coins server-side. Returns the coins credited and remaining claims
  /// for today. Rewards are coins (virtual currency), never cash.
  static Future<Map<String, dynamic>> claimUnityReward() async {
    final res = await _invoke('claim-unity-reward');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-unity-reward failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-unity-reward returned an unexpected response');
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

  /// Claims the daily spin-wheel reward.
  ///
  /// The `claim-spin` Edge Function picks a weighted-random reward
  /// server-side. Returns reward_coins and spins_remaining.
  static Future<Map<String, dynamic>> claimSpin() async {
    final res = await _invoke('claim-spin');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      if (res.status == 409 && data is Map<String, dynamic>) return data;
      throw Exception('claim-spin failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-spin returned an unexpected response');
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
