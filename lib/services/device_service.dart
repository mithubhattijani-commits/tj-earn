import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'supabase_service.dart';

/// Device fingerprinting for anti-fraud.
///
/// Generates a SHA-256 hash of the Android ID + model. The hash (not the
/// raw ID) is sent to the `register-device` Edge Function, which tracks
/// how many users share a device. Devices with >3 users are flagged for
/// admin review.
///
/// Privacy: only the hash leaves the device, never the raw Android ID.
class DeviceService {
  static bool _inFlight = false;

  /// Registers the current device with the server.
  ///
  /// Call once per login/session. Failures are silent (never blocks login).
  /// Guarded against concurrent calls so rebuilds can't pile duplicate
  /// registrations into the startup queue.
  static Future<void> register() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final android = await deviceInfo.androidInfo;

      // Hash the Android ID (stable per device + app signing key)
      final raw = '${android.id}:${android.model}:${android.brand}';
      final hash = sha256.convert(utf8.encode(raw)).toString();

      final model = '${android.brand} ${android.model}'.trim();

      await SupabaseService.registerDevice(hash, model);
    } catch (_) {
      // Silent: device registration must never block the user.
    } finally {
      _inFlight = false;
    }
  }
}
