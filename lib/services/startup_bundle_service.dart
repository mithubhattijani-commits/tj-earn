import 'admin_status.dart';
import 'supabase_service.dart';

/// Single-call startup bundle (Jaani, 2 Nov 2026).
///
/// Replaces 4 separate startup calls (balance, streak, onboarding,
/// admin probe) with ONE `get-startup-bundle` Edge Function call — 75%
/// fewer server round trips on the critical startup path, which is what
/// hung the app on slow connections (ANR).
///
/// The bundle is fetched once per session and cached; every widget reads
/// its slice from the same cached map. Idempotent — concurrent callers
/// share one in-flight future, so even if several widgets ask at once
/// only ONE network call ever happens. Never throws into the UI: a
/// failed load returns null and widgets render their existing
/// error/loading states.
class StartupBundleService {
  static Future<Map<String, dynamic>?>? _bundleFuture;
  static Map<String, dynamic>? _cached;

  /// Cached bundle map, or null if not loaded / load failed.
  static Map<String, dynamic>? get cached => _cached;

  /// Fetch the bundle once; concurrent callers share the same future.
  /// Never throws — returns null on any failure.
  static Future<Map<String, dynamic>?> loadBundle() {
    _bundleFuture ??= _fetch();
    return _bundleFuture!;
  }

  static Future<Map<String, dynamic>?> _fetch() async {
    try {
      final data = await SupabaseService.getStartupBundle();
      _cached = data;
      // The admin flag flows into the existing AdminStatus notifier so
      // admin UI gating keeps working unchanged.
      AdminStatus.notifier.value = data['is_admin'] == true;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Balance slice in coins, or null if unavailable.
  static int? get balanceCoins {
    final v = _cached?['balance_coins'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  /// Streak row slice, or null.
  static Map<String, dynamic>? get streak {
    final s = _cached?['streak'];
    return s is Map ? s.cast<String, dynamic>() : null;
  }

  /// Completed onboarding task keys (empty when unavailable).
  static List<String> get onboardingCompleted {
    final o = _cached?['onboarding_completed'];
    if (o is List) return o.map((e) => e.toString()).toList();
    return const [];
  }

  /// Clear on logout so the next session refetches.
  static void reset() {
    _bundleFuture = null;
    _cached = null;
  }
}
