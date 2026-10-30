import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'supabase_service.dart';
import 'validation.dart';

/// In-app updater for sideloaded (website APK) installs.
///
/// Flow: version-check -> dialog -> download to cache -> platform install
/// intent. The install keeps the app's data: same package
/// (com.tjearn.app) + same signing key + a higher versionCode means Android
/// treats it as an update, never a reinstall. Play Store installs are
/// updated by Play itself and never reach this path in practice.
class UpdaterService {
  static const _channel = MethodChannel('tj_earn/updater');

  static Future<void> checkForUpdate(BuildContext context) async {
    if (!AppConfig.isConfigured) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final latest = await SupabaseService.getLatestVersion();
      if (latest == null) return;
      final latestCode = latest['version_code'];
      final apkUrl = latest['apk_url'];
      if (latestCode is! int || apkUrl is! String || apkUrl.isEmpty) return;
      if (!isNewerVersion(latestCode, currentCode)) return;
      if (!context.mounted) return;
      final localizations = AppLocalizations.of(context)!;
      final wantUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.updateAvailable),
          content: Text(
            '${latest['version_name'] ?? ''}\n${latest['notes'] ?? ''}'.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(localizations.updateLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(localizations.updateNow),
            ),
          ],
        ),
      );
      if (wantUpdate != true || !context.mounted) return;
      await _downloadAndInstall(context, apkUrl);
    } catch (_) {
      // Update checks must never break the app: fail silently.
    }
  }

  /// Manual update check with distinguished messages (Jaani 31 Oct 2026).
  /// Unlike [checkForUpdate] (silent on launch), this tells the user
  /// exactly what happened:
  /// - "up to date" when already on the latest version
  /// - "no internet" when offline
  /// - "update info not found" when the version record is unreachable
  static Future<void> checkManually(BuildContext context) async {
    if (!AppConfig.isConfigured) return;
    final localizations = AppLocalizations.of(context);
    if (localizations == null || !context.mounted) return;

    // 1. Connectivity probe first.
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.noInternetForUpdate)),
      );
      return;
    }

    // 2. Fetch version info from Supabase.
    Map<String, dynamic>? latest;
    try {
      latest = await SupabaseService.getLatestVersion();
    } on SocketException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.noInternetForUpdate)),
      );
      return;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.updateInfoNotFound)),
      );
      return;
    }

    // 3. Validate the version record.
    if (latest == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.updateInfoNotFound)),
      );
      return;
    }
    final latestCode = latest['version_code'];
    final apkUrl = latest['apk_url'];
    if (latestCode is! int || apkUrl is! String || apkUrl.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.updateInfoNotFound)),
      );
      return;
    }

    // 4. Compare versions.
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    if (!isNewerVersion(latestCode, currentCode)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.appUpToDate)),
      );
      return;
    }

    // 5. Newer version available — show the update dialog.
    if (!context.mounted) return;
    final wantUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.updateAvailable),
        content: Text(
          '${latest?['version_name'] ?? ''}\n${latest?['notes'] ?? ''}'.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(localizations.updateLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(localizations.updateNow),
          ),
        ],
      ),
    );
    if (wantUpdate != true || !context.mounted) return;
    await _downloadAndInstall(context, apkUrl);
  }

  /// Quick connectivity probe used by [checkManually] to distinguish
  /// "no internet" from other failures.
  static Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('znyaxxkhhopdqrvxhxmb.supabase.co')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    String apkUrl,
  ) async {
    final localizations = AppLocalizations.of(context)!;
    final canInstall =
        await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) {
      await _channel.invokeMethod<void>('openInstallSettings');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.installPermissionNeeded)),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.downloading)),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tj-earn-update.apk');
    final request = http.Request('GET', Uri.parse(apkUrl));
    final streamed = await http.Client().send(request);
    if (streamed.statusCode != 200) return;
    final sink = file.openWrite();
    await streamed.stream.pipe(sink);
    await _channel.invokeMethod<void>('installApk', {'path': file.path});
  }
}
