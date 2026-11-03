import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'validation.dart';

/// In-app updater for sideloaded (website APK) installs.
///
/// Doner-style flow (Jaani, 3 Nov 2026 — "jesy Doner update hoti ha wesy"):
/// the app fetches a small JSON manifest from the website
/// (https://nigraantv.xyz/apps/tj-earn-version.json) and compares its
/// versionCode with the installed one. When a newer version exists, the
/// user is offered an update; the new APK downloads via Dart HttpClient
/// (follows GitHub's 302 redirects — DownloadManager did not, Jaani 3 Nov
/// 2026 fix) with a live progress banner, then the system install prompt
/// fires. A sideloaded app can NEVER install silently — Android always
/// requires the user's install tap.
///
/// Manifest format (same as Doner's):
///   {"versionCode": 16, "versionName": "1.0.15",
///    "url": "https://.../tj-earn-v1.0.15.apk", "notes": "What's new"}
///
/// The updater is inert until that manifest exists: a missing or
/// unreachable manifest simply means "no update prompt, no error".
///
/// Launch check never nags: a version the user dismissed ("Later") is
/// recorded under 'dismissed_update_code' and never prompts again on
/// launch; a future newer version prompts again. The manual check shows
/// its dialog regardless of dismissal.
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

  /// Website manifest (Doner-style). Published separately by the parent
  /// with the stable APK download link; until it exists the checker
  /// stays silent.
  static const String manifestUrl =
      'https://nigraantv.xyz/apps/tj-earn-version.json';

  /// VersionCode the user dismissed with "Later" — never re-prompted
  /// on launch. A newer versionCode prompts again.
  static const String _dismissedKey = 'dismissed_update_code';

  /// Fetches the version manifest from the website (Doner-style).
  /// Returns {versionCode, versionName, url, notes} or null on ANY
  /// failure (no network, 404, bad JSON). Never throws.
  static Future<Map<String, dynamic>?> _fetchManifest() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final code = data['versionCode'];
      final url = data['url'];
      if (code is! int || url is! String || url.isEmpty) return null;
      return <String, dynamic>{
        'versionCode': code,
        'versionName': (data['versionName'] as String?) ?? 'v$code',
        'url': url,
        'notes': (data['notes'] as String?) ?? '',
      };
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<int> _dismissedCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_dismissedKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _recordDismissed(int versionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedKey, versionCode);
    } catch (_) {
      // Dismissal is best-effort; a missed write only re-prompts once.
    }
  }

  /// Launch check: silent unless a newer, NOT-dismissed version exists.
  /// Never throws and never blocks the UI — safe from addPostFrameCallback.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (!AppConfig.isConfigured) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final latest = await _fetchManifest();
      if (latest == null) return;
      final latestCode = latest['versionCode'] as int;
      final apkUrl = latest['url'] as String;
      if (!isNewerVersion(latestCode, currentCode)) return;
      if (await _dismissedCode() == latestCode) return;
      if (!context.mounted) return;
      final localizations = AppLocalizations.of(context)!;
      final wantUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.updateAvailable),
          content: Text(
            '${latest['versionName'] ?? ''}\n${latest['notes'] ?? ''}'.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _recordDismissed(latestCode);
                Navigator.of(ctx).pop(false);
              },
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
  /// - "update info not found" when the manifest is unreachable
  /// Shows the update dialog regardless of dismissal.
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

    // 2. Fetch version manifest from the website (Doner-style).
    Map<String, dynamic>? latest;
    try {
      latest = await _fetchManifest();
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
    final latestCode = latest['versionCode'];
    final apkUrl = latest['url'];
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
          '${latest?['versionName'] ?? ''}\n${latest?['notes'] ?? ''}'.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _recordDismissed(latestCode);
              Navigator.of(ctx).pop(false);
            },
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
      final result = await InternetAddress.lookup('nigraantv.xyz')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the APK via Dart HttpClient and fires the install prompt.
  ///
  /// FIX (Jaani, 3 Nov 2026 — "App k ander hi update hona chahiye"): the old
  /// implementation used Android DownloadManager, which FAILS on GitHub
  /// release URLs (302 redirect to objects.githubusercontent.com — the
  /// manager does not follow it reliably, download ends "failed" and the UI
  /// shows "something went wrong"). This version uses Dart's HttpClient
  /// (same as Doner's working updater): HttpClient follows redirects
  /// automatically, streams to a file in the app cache dir with live
  /// progress, then fires the system install prompt via FileProvider.
  /// The app is never locked behind a modal — the banner shows progress.
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
      final file = await _downloadApkFile(apkUrl, progress);
      if (file == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.genericError)),
          );
        }
        return;
      }
      if (context.mounted) {
        await _channel.invokeMethod<void>(
            'installApk', {'path': file.path});
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

  /// Streams the APK to the app cache dir via HttpClient.
  ///
  /// HttpClient follows HTTP redirects automatically (followRedirects=true
  /// by default), so GitHub's 302 to the release asset works. Returns the
  /// file on success, null on any failure. Progress (downloaded, total)
  /// is pushed to [progress]; total is 0 when the server hides its size.
  static Future<File?> _downloadApkFile(
    String apkUrl,
    ValueNotifier<_DownloadProgress> progress,
  ) async {
    HttpClient? client;
    try {
      final cacheDir = await _apkCacheDir();
      final file = File('${cacheDir.path}/tj-earn-update.apk');
      if (await file.exists()) await file.delete();
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..followRedirects = true
        ..maxRedirects = 5;
      final request = await client.getUrl(Uri.parse(apkUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Download timed out'),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final total = response.contentLength;
      var downloaded = 0;
      var lastBytes = 0;
      var lastChange = DateTime.now();
      final sink = file.openWrite();
      await for (final chunk in response) {
        downloaded += chunk.length;
        sink.add(chunk);
        final now = DateTime.now();
        if (downloaded > lastBytes) {
          lastBytes = downloaded;
          lastChange = now;
        }
        final stalled =
            now.difference(lastChange).inSeconds >= 60;
        progress.value = _DownloadProgress(
          downloaded: downloaded,
          total: total,
          stalled: stalled,
        );
      }
      await sink.close();
      if (await file.length() == 0) return null;
      return file;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// App cache directory for the downloaded APK.
  static Future<Directory> _apkCacheDir() async {
    // MethodChannel already exists for installer; reuse a cache path via
    // the channel to avoid adding path_provider dependency.
    final path = await _channel.invokeMethod<String>('apkCacheDir') ??
        '/data/user/0/com.tjearn.app/cache';
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
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
