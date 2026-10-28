import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// All Supabase access for the app.
///
/// SECURITY: the app only ever *reads* the wallet. It never inserts into the
/// ledger — there is deliberately no function here that writes coins. Coin
/// grants happen only inside Edge Functions (service role) after a verified
/// provider callback. A grep for `from('ledger').insert` across lib/ must
/// return zero matches.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static User? get currentUser => client.auth.currentUser;

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
}
