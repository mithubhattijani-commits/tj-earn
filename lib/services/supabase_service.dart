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

  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static User? get currentUser => client.auth.currentUser;

  static String? get userEmail => currentUser?.email;

  /// Balance from the server (SUM of the ledger). Never computed locally
  /// from anything the app could edit.
  static Future<int> getBalance() async {
    final res = await client.functions.invoke('get-balance');
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
    final rows = await client
        .from('ledger')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Own withdrawal requests, newest first.
  static Future<List<Map<String, dynamic>>> getWithdrawals() async {
    final user = currentUser;
    if (user == null) throw Exception('not signed in');
    final rows = await client
        .from('withdrawals')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(50);
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
    final res = await client.functions.invoke(
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
    final res = await client.functions.invoke('get-referral');
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
    final res = await client.functions.invoke(
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
      final res = await client.functions.invoke('version-check');
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
    final res = await client.functions.invoke('claim-unity-reward');
    final data = res.data;
    if (res.status != 200) {
      final message =
          data is Map && data['error'] is String ? data['error'] : 'failed';
      throw Exception('claim-unity-reward failed: $message');
    }
    if (data is Map<String, dynamic>) return data;
    throw Exception('claim-unity-reward returned an unexpected response');
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
    final res = await client.functions.invoke(
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
    final res = await client.functions.invoke(
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
    final res = await client.functions.invoke(
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
    final res = await client.functions.invoke('review-referral', body: body);
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
