import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_status.dart';
import 'supabase_service.dart';

/// Cache-first startup bundle (Jaani, 2 Nov 2026 — PERMANENT hang fix).
///
/// How professional apps (Facebook, banking apps) do startup: the UI
/// NEVER waits for the network. The last-known bundle is read from
/// SharedPreferences and shown INSTANTLY (<100ms); a single background
/// refresh then updates the cache and notifies listeners. If the server
/// is slow or down, the app keeps working with cached data.
///
/// Flow:
/// 1. `main()` calls [initCache] before runApp (local disk read, fast).
/// 2. Widgets read the sync slice getters in initState (instant) and
///    call [refreshInBackground] (fire-and-forget, throttled).
/// 3. [refreshDone] ticks on every completed attempt (success OR
///    failure) — widgets re-read the sync getters and rebuild.
/// 4. [bundleNotifier] fires with fresh data on success (for any
///    listener that wants the raw map).
///
/// RULE: no widget may `await` a network call in initState().
class StartupBundleService {
  static const _prefsKey = 'startup_bundle';
  static const _prefsTimeKey = 'startup_bundle_time';

  /// Throttle: at most one background refresh per 30s per session.
  static const _minRefreshGap = Duration(seconds: 30);

  static Map<String, dynamic>? _cached;
  static bool _refreshing = false;
  static DateTime? _lastRefreshAttempt;

  /// Fires with fresh bundle data on every SUCCESSFUL refresh.
  static final ValueNotifier<Map<String, dynamic>?> bundleNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// Ticks (increments) on EVERY completed refresh attempt, success or
  /// failure. Widgets listen to this and re-read the sync slice getters —
  /// this is what lets a first-run widget leave its spinner and show a
  /// retry when the server is unreachable.
  static final ValueNotifier<int> refreshDone = ValueNotifier(0);

  /// Cached bundle map, or null if never loaded.
  static Map<String, dynamic>? get cached => _cached;

  /// True once any bundle (fresh or cached) is in memory.
  static bool get hasCache => _cached != null;

  /// True while a refresh is in flight.
  static bool get isRefreshing => _refreshing;

  /// Load the last-known bundle from local disk. Called once in main()
  /// before runApp — a local read, never a network call.
  static Future<void> initCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cached = decoded;
        bundleNotifier.value = _cached;
      } else if (decoded is Map) {
        _cached = Map<String, dynamic>.from(decoded);
        bundleNotifier.value = _cached;
      }
    } catch (_) {
      // Corrupt cache: ignore it; the background refresh replaces it.
      _cached = null;
    }
  }

  /// Returns cached data INSTANTLY (null on very first run) and triggers
  /// one background refresh. Never blocks, never throws.
  static Map<String, dynamic>? getBundleSync() {
    _refreshInBackground();
    return _cached;
  }

  /// Fire-and-forget refresh. Concurrent callers share one in-flight
  /// fetch; throttled to [_minRefreshGap] per session.
  static void refreshInBackground() => _refreshInBackground();

  static void _refreshInBackground() {
    if (_refreshing) return;
    final now = DateTime.now();
    if (_lastRefreshAttempt != null &&
        now.difference(_lastRefreshAttempt!) < _minRefreshGap) {
      return;
    }
    _refreshing = true;
    _lastRefreshAttempt = now;
    // ignore: unawaited_futures
    SupabaseService.getStartupBundle().then((data) {
      _apply(data);
    }).catchError((_) {
      // Server slow/down: keep serving the cache. Still tick so
      // first-run widgets can leave the spinner and show a retry.
      refreshDone.value++;
    }).whenComplete(() {
      _refreshing = false;
    });
  }

  /// Force a fresh fetch now (retry buttons). Bypasses the throttle.
  /// Never throws — on failure the old cache is kept and [refreshDone]
  /// still ticks so the UI can show its error state.
  static Future<void> refreshNow() async {
    if (_refreshing) return;
    _refreshing = true;
    _lastRefreshAttempt = DateTime.now();
    try {
      final data = await SupabaseService.getStartupBundle();
      _apply(data);
    } catch (_) {
      refreshDone.value++;
    } finally {
      _refreshing = false;
    }
  }

  static void _apply(Map<String, dynamic> data) {
    _cached = data;
    // The admin flag flows into the existing notifier (fail-closed).
    try {
      AdminStatus.notifier.value = data['is_admin'] == true;
    } catch (_) {}
    bundleNotifier.value = data;
    refreshDone.value++;
    // Persist for the next cold start (fire-and-forget).
    unawaited(_persist(data));
  }

  static Future<void> _persist(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data));
      await prefs.setInt(
          _prefsTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Legacy API — prefer the sync slice getters + [refreshDone].
  /// Returns the cache immediately when present, otherwise performs one
  /// fetch. Never throws (returns null on failure).
  static Future<Map<String, dynamic>?> loadBundle() async {
    if (_cached != null) return _cached;
    await refreshNow();
    return _cached;
  }

  // ---- Sync slice getters (read from the in-memory cache) ----

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
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  /// Completed onboarding task keys (empty when unavailable).
  static List<String> get onboardingCompleted {
    final o = _cached?['onboarding_completed'];
    if (o is List) return o.map((e) => e.toString()).toList();
    return const [];
  }

  /// Clear on logout so the next account starts fresh. Sync signature
  /// (existing call sites stay unchanged); disk clear is fire-and-forget.
  static void reset() {
    _cached = null;
    _refreshing = false;
    _lastRefreshAttempt = null;
    bundleNotifier.value = null;
    unawaited(_clearPersisted());
  }

  static Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_prefsTimeKey);
    } catch (_) {}
  }
}
