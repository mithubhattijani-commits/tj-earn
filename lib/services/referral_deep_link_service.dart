import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';
import 'validation.dart';

/// Referral deep linking (Jaani, 3 Nov 2026).
///
/// When a user shares their referral link (https://nigraantv.xyz/earn/?ref=CODE):
/// - If the app is installed and the link is clicked, the OS opens the app
///   directly with the link (via app_links + Android App Links).
/// - On web, the ?ref= query parameter is read from Uri.base.
/// - The referral code is stored as "pending" in SharedPreferences.
/// - After the user signs up / signs in, the pending code is auto-applied
///   via SupabaseService.applyReferral — no manual code entry needed.
///
/// Task E (12 Nov 2026): deferred attribution — if the app was installed
/// after a referral click (no link reaches the app), the first launch asks
/// GET https://nigraan-admin-api.mithubhattijani.workers.dev/api/ref/match for a
/// code matched to this device (fingerprint/IP, valid 7 days). A matched
/// code is stored as pending the same way. The sign-up form also prefills
/// the code from the pending code or the clipboard.
///
/// All operations are best-effort and never block the UI. Timeouts bound
/// every step per the APP ROBUSTNESS RULE.
class ReferralDeepLinkService {
  static const _pendingKey = 'pending_referral_code';
  // Task E (12 Nov 2026): deferred attribution (first launch only).
  static const _deferredCheckedKey = 'deferred_referral_checked';
  static const _deferredMatchUrl =
      'https://nigraan-admin-api.mithubhattijani.workers.dev/api/ref/match';

  ReferralDeepLinkService._();
  static final ReferralDeepLinkService instance =
      ReferralDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;
  // In-flight deferred-match request, so concurrent callers share it.
  Future<String?>? _deferredCheckFuture;

  /// Initializes deep link handling. Call once at app startup (fire-and-forget).
  /// Never throws, never blocks.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // 0. Deferred attribution (Task E, 12 Nov 2026): first launch only,
      // ask the website whether this install clicked a referral link in
      // the last 7 days. Fire-and-forget — never blocks startup.
      unawaited(checkDeferredReferral());

      // 1. Web: read ?ref= from the current URL.
      if (kIsWeb) {
        final ref = Uri.base.queryParameters['ref'];
        if (ref != null && ref.isNotEmpty) {
          await _storePendingCode(ref);
        }
      }

      // 2. Mobile: check if app was launched via a deep link.
      try {
        final initialLink = await _appLinks.getInitialLink().timeout(
          const Duration(seconds: 5),
        );
        if (initialLink != null) {
          _handleIncomingUri(initialLink);
        }
      } catch (_) {
        // Best-effort: ignore failures.
      }

      // 3. Mobile: listen for links while app is running.
      _linkSubscription = _appLinks.uriLinkStream.listen(
        _handleIncomingUri,
        onError: (_) {},
      );
    } catch (_) {
      // Never let deep link init break the app.
    }
  }

  /// Deferred attribution (Task E, 12 Nov 2026).
  ///
  /// On FIRST launch only, asks GET
  /// https://nigraan-admin-api.mithubhattijani.workers.dev/api/ref/match
  /// whether this device clicked a referral link recently. The website
  /// matches the request (fingerprint/IP) against referral clicks from
  /// the last 7 days and returns the code, if any. A matched code is
  /// stored as pending (never overwriting a deep-link code) and applied
  /// after sign-up by [autoApplyPendingCode].
  ///
  /// Returns the matched code, or null. Never throws. Concurrent calls in
  /// one app run share a single in-flight request; a completed JSON
  /// answer is remembered per install, while a failed request retries on
  /// the next launch.
  Future<String?> checkDeferredReferral() {
    final inFlight = _deferredCheckFuture;
    if (inFlight != null) return inFlight;
    _deferredCheckFuture = _runDeferredCheck();
    return _deferredCheckFuture!;
  }

  Future<String?> _runDeferredCheck() async {
    try {
      return await _checkDeferredReferral();
    } finally {
      _deferredCheckFuture = null;
    }
  }

  Future<String?> _checkDeferredReferral() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_deferredCheckedKey) == true) {
        return await getPendingCode();
      }
      if (kIsWeb) {
        // Web attribution comes from the ?ref= parameter (see init),
        // not from a deferred match.
        await prefs.setBool(_deferredCheckedKey, true);
        return null;
      }
      // A deep link already won: keep it and don't spend the match call.
      final existing = await getPendingCode();
      if (existing != null) {
        await prefs.setBool(_deferredCheckedKey, true);
        return existing;
      }
      final response = await http
          .get(
            Uri.parse(_deferredMatchUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      // Only a parseable JSON answer counts as "checked": an HTML error
      // page (endpoint not reached) must retry on the next launch.
      await prefs.setBool(_deferredCheckedKey, true);
      final code = _codeFromMatchResponse(decoded);
      if (code == null) return null;
      await _storePendingCode(code);
      return code;
    } catch (_) {
      return null;
    }
  }

  /// Pulls the referral code out of a /api/ref/match JSON body.
  /// Accepts {"code": "ABCDEFGH"} (also "referral_code" / "ref", and a
  /// nested "data" object). Anything else is not a match.
  String? _codeFromMatchResponse(Map<String, dynamic> json) {
    final candidates = <Object?>[
      json['code'],
      json['referral_code'],
      json['ref'],
      if (json['data'] is Map<String, dynamic>)
        (json['data'] as Map<String, dynamic>)['code'],
    ];
    for (final candidate in candidates) {
      if (candidate is String) {
        final code = candidate.trim().toUpperCase();
        if (isValidReferralCode(code)) return code;
      }
    }
    return null;
  }

  /// Extracts the referral code from an incoming URI and stores it.
  void _handleIncomingUri(Uri uri) {
    try {
      // Accept ?ref=CODE on any nigraantv.xyz/earn/ link.
      final ref = uri.queryParameters['ref'];
      if (ref != null && ref.isNotEmpty) {
        unawaited(_storePendingCode(ref));
      }
    } catch (_) {}
  }

  /// Validates and stores a referral code as pending.
  Future<void> _storePendingCode(String rawCode) async {
    try {
      final code = rawCode.trim().toUpperCase();
      if (!isValidReferralCode(code)) return;
      final prefs = await SharedPreferences.getInstance();
      // Don't overwrite an existing pending code.
      if (prefs.getString(_pendingKey) == null) {
        await prefs.setString(_pendingKey, code);
      }
    } catch (_) {}
  }

  /// Returns the pending referral code, or null if none.
  Future<String?> getPendingCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_pendingKey);
      if (code != null && isValidReferralCode(code)) return code;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears the pending referral code (after successful apply or if invalid).
  Future<void> clearPendingCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (_) {}
  }

  /// Reads the clipboard for a referral code (same scan as the
  /// auto-apply fallback). Used by the sign-up form to prefill the
  /// referral field. Returns null when nothing usable is on the
  /// clipboard. Never throws.
  Future<String?> readClipboardReferralCode() => _checkClipboardForCode();

  /// Stores a referral code entered in the sign-up form as pending, so
  /// it is auto-applied after sign-up. The code the user explicitly
  /// entered wins over any deferred/deep-link code. Invalid codes are
  /// ignored. Never throws.
  Future<void> savePendingCode(String rawCode) async {
    try {
      final code = rawCode.trim().toUpperCase();
      if (!isValidReferralCode(code)) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, code);
    } catch (_) {}
  }

  /// Called after successful sign-in/sign-up. Auto-applies the pending
  /// referral code if one exists. Returns the applied code, or null.
  ///
  /// This is best-effort: if the code was already applied, is invalid,
  /// or is the user's own code, the server rejects it and we clear it.
  Future<String?> autoApplyPendingCode() async {
    var code = await getPendingCode();
    // Fallback: check clipboard for a referral code (user may have copied
    // it from the website download page before installing).
    if (code == null && !kIsWeb) {
      code = await _checkClipboardForCode();
      if (code != null) {
        await _storePendingCode(code);
      }
    }
    if (code == null) return null;
    try {
      await SupabaseService.applyReferral(code).timeout(
        const Duration(seconds: 25),
      );
      await clearPendingCode();
      return code;
    } catch (_) {
      // Server rejected (duplicate, self-referral, invalid, etc.).
      // Clear so we don't retry forever.
      await clearPendingCode();
      return null;
    }
  }

  /// Checks the clipboard for a valid referral code pattern.
  /// Used as fallback when the user copied the code from the website.
  Future<String?> _checkClipboardForCode() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain).timeout(
        const Duration(seconds: 5),
      );
      final text = data?.text?.trim().toUpperCase() ?? '';
      // Check if clipboard contains a valid code (exact or embedded in link).
      if (isValidReferralCode(text)) return text;
      // Try to extract from a referral link.
      final match = RegExp(r'[?&]ref=([A-Z0-9]{8})').firstMatch(text);
      if (match != null) {
        final extracted = match.group(1)!;
        if (isValidReferralCode(extracted)) return extracted;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }
}
