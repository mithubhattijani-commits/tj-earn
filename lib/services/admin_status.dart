import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// In-memory admin-status cache for the current session.
///
/// Probed ONCE per session via [SupabaseService.referralStats]: 200 = admin,
/// [AdminAccessDenied] (403/503) = not admin, anything else = unknown (left
/// null and retried on the next probe). The Edge Function gate is the real
/// guard — this is visibility only. Never persisted; cleared on logout.
class AdminStatus {
  static final ValueNotifier<bool?> notifier = ValueNotifier<bool?>(null);
  static bool _probing = false;

  /// Runs the probe unless a result is already cached. Safe to call from
  /// build methods: it returns immediately when a result is cached or a
  /// probe is already in flight.
  static Future<void> probe() async {
    if (notifier.value != null || _probing) return;
    _probing = true;
    try {
      await SupabaseService.referralStats();
      notifier.value = true;
    } on AdminAccessDenied {
      notifier.value = false;
    } catch (_) {
      // Unknown — leave null so the next login retries.
    } finally {
      _probing = false;
    }
  }

  static void reset() {
    notifier.value = null;
    _probing = false;
  }
}
