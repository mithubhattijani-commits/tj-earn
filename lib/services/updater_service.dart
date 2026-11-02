import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
/// Live download-progress state (Jaani, 2 Nov 2026): the update download
/// must show visible progress in the app — percent + MB downloaded/total —
/// so the user never stares at a stuck screen wondering if it is downloading.
class _DownloadProgress {
  final int downloaded;
  final int total;
  final bool stalled;

  const _DownloadProgress({
    required this.downloaded,
    required this.total,
    required this.stalled,
  });
}

/// Non-blocking download progress banner (Jaani, 2 Nov 2026): sits at the
/// bottom of the screen while the APK downloads in the background — the
/// app is never locked behind a modal dialog.
class _DownloadProgressBanner extends StatelessWidget {
  final ValueNotifier<_DownloadProgress> progress;
  final AppLocalizations localizations;

  const _DownloadProgressBanner({
    required this.progress,
    required this.localizations,
  });

  static String _mb(int bytes) {
    final double mb = bytes / 1048576.0;
    return mb.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16.0,
      right: 16.0,
      bottom: 32.0,
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ValueListenableBuilder<_DownloadProgress>(
            valueListenable: progress,
            builder: (BuildContext ctx, _DownloadProgress p, Widget? _) {
              final int rawPct =
                  p.total > 0 ? ((p.downloaded / p.total) * 100).round() : 0;
              final int pct = rawPct < 0 ? 0 : (rawPct > 100 ? 100 : rawPct);
              final double? barValue =
                  p.total > 0 ? p.downloaded / p.total : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    localizations.downloading,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  LinearProgressIndicator(value: barValue),
                  const SizedBox(height: 8.0),
                  Text('${_mb(p.downloaded)} / ${_mb(p.total)} MB \u2022 $pct%'),
                  if (p.stalled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        localizations.downloadStalled,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

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

  /// Download via Android DownloadManager (Jaani, 2 Nov 2026 — permanent
  /// fix for background-killed downloads): the system process handles the
  /// download, so it survives app background/kill, shows a notification with
  /// progress, and auto-resumes on network interruption. We poll for
  /// completion then fire the install intent.
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
    final ValueNotifier<_DownloadProgress> progress =
        ValueNotifier<_DownloadProgress>(
      const _DownloadProgress(downloaded: 0, total: 0, stalled: false),
    );
    OverlayEntry? banner;
    if (context.mounted) {
      final OverlayState? overlay =
          Navigator.of(context, rootNavigator: true).overlay;
      if (overlay != null) {
        banner = OverlayEntry(
          builder: (BuildContext ctx) => _DownloadProgressBanner(
            progress: progress,
            localizations: localizations,
          ),
        );
        overlay.insert(banner);
      }
    }
    try {
      final downloadId = await _channel.invokeMethod<int>(
        'downloadApk',
        {'url': apkUrl, 'fileName': 'tj-earn-update.apk'},
      );
      if (downloadId == null) return;
      int lastBytes = 0;
      DateTime lastChange = DateTime.now();
      // Poll DownloadManager for completion (max ~10 minutes).
      for (var i = 0; i < 300; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final status = await _channel.invokeMethod<Map>('downloadStatus', {
          'downloadId': downloadId,
        });
        final s = status?['status'] as String?;
        final int downloaded = (status?['bytesDownloaded'] as int?) ?? 0;
        final int total = (status?['bytesTotal'] as int?) ?? 0;
        final DateTime now = DateTime.now();
        if (downloaded > lastBytes) {
          lastBytes = downloaded;
          lastChange = now;
        }
        final bool stalled = (s == 'running' || s == 'pending') &&
            now.difference(lastChange).inSeconds >= 60;
        progress.value = _DownloadProgress(
          downloaded: downloaded,
          total: total,
          stalled: stalled,
        );
        if (s == 'success') {
          final uri = status?['localUri'] as String? ?? '';
          final path = _uriToPath(uri);
          if (path != null && context.mounted) {
            await _channel.invokeMethod<void>('installApk', {'path': path});
          }
          return;
        } else if (s == 'failed' || s == 'not_found') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(localizations.genericError)),
            );
          }
          return;
        }
        // running/pending/paused -> keep polling; banner shows live progress.
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.genericError)),
        );
      }
    } finally {
      banner?.remove();
      progress.dispose();
    }
  }

  /// Convert a DownloadManager local URI (file:// or content://) to a path
  /// usable by the install intent. For content:// URIs we copy to cache.
  static String? _uriToPath(String uri) {
    if (uri.isEmpty) return null;
    if (uri.startsWith('file://')) {
      return Uri.parse(uri).toFilePath();
    }
    return null; // content:// handled by system; shouldn't happen with our dest
  }
}
