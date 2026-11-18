import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../app_navigator.dart';
import '../config.dart';
import 'validation.dart';

/// In-app updater for sideloaded (website APK) installs.
///
/// Flow: version-check -> dialog -> DownloadManager download ->
/// platform install intent. The install keeps the app's data: same
/// package (com.tjearn.app) + same signing key + a higher versionCode
/// means Android treats it as an update, never a reinstall. Play Store
/// installs are updated by Play itself and never reach this path in
/// practice.
///
/// BACKGROUND-DOWNLOAD REWORK (Jaani, 3 Nov 2026): the download state
/// is GLOBAL now — [UpdateDownloadState] (a singleton) holds the live
/// progress notifier + download id, the progress banner is inserted
/// through the global [appNavigatorKey]'s overlay (survives navigation),
/// the in-flight download id is persisted in SharedPreferences so a
/// cold start re-attaches the banner/polling, and the install prompt is
/// shown through the global navigator even if the user left Settings.
/// A manifest-registered [DownloadCompleteReceiver] (native) fires the
/// install intent directly when the download finishes while the app is
/// dead. DownloadManager (system process) handles the bytes in all
/// cases: survives app background/kill, shows a notification with
/// progress, auto-resumes on network interruption, follows redirects
/// natively (this is why the MethodChannel path replaced the old
/// HttpClient download — no 302 workarounds needed).

/// Resolves the effective total size of an in-flight APK download.
///
/// DownloadManager reports `COLUMN_TOTAL_SIZE_BYTES` as -1 while the
/// total is unknown (headers not in yet, or the server omits
/// Content-Length). A -1/0 reported total must NEVER be displayed or
/// used as a divisor: fall back to [knownTotal] (the APK's HTTP
/// Content-Length, fetched before the download starts) when available,
/// else 0 meaning "unknown".
int resolveDownloadTotal({required int reportedTotal, int? knownTotal}) {
  if (reportedTotal > 0) return reportedTotal;
  if (knownTotal != null && knownTotal > 0) return knownTotal;
  return 0;
}

/// Formats a byte count as megabytes with one decimal, e.g. `12.3`.
String formatMegabytes(int bytes) =>
    (bytes / 1048576.0).toStringAsFixed(1);

class DownloadProgress {
  /// Bytes downloaded so far.
  final int downloaded;

  /// Total bytes as reported by DownloadManager; -1 or 0 when unknown.
  final int total;
  final bool stalled;

  const DownloadProgress({
    required this.downloaded,
    required this.total,
    required this.stalled,
  });

  /// Effective total: the reported total when known, else [knownTotal]
  /// (APK Content-Length), else 0 (unknown).
  int effectiveTotal(int? knownTotal) =>
      resolveDownloadTotal(reportedTotal: total, knownTotal: knownTotal);

  /// Whole-percent completion, 0-100. 0 while the total is unknown —
  /// never a fake number.
  int percent({int? knownTotal}) {
    final int t = effectiveTotal(knownTotal);
    if (t <= 0) return 0;
    final int p = ((downloaded / t) * 100).round();
    if (p < 0) return 0;
    if (p > 100) return 100;
    return p;
  }

  /// 0.0-1.0 fraction for a determinate progress bar, or null while the
  /// total is unknown (indeterminate bar).
  double? fraction({int? knownTotal}) {
    final int t = effectiveTotal(knownTotal);
    if (t <= 0) return null;
    final double f = downloaded / t;
    if (f < 0.0) return 0.0;
    if (f > 1.0) return 1.0;
    return f;
  }

  /// Bytes still to download, 0 while the total is unknown.
  int remainingBytes({int? knownTotal}) {
    final int t = effectiveTotal(knownTotal);
    if (t <= 0) return 0;
    final int r = t - downloaded;
    return r < 0 ? 0 : r;
  }

  /// Main progress line, e.g. `12.3 / 25.0 MB • 49%`. While the total
  /// is unknown: `12.3 MB downloaded` — the downloaded amount is real
  /// even when the total is not.
  String mainLine({int? knownTotal}) {
    final int t = effectiveTotal(knownTotal);
    if (t <= 0) return '${formatMegabytes(downloaded)} MB downloaded';
    return '${formatMegabytes(downloaded)} / ${formatMegabytes(t)} MB'
        ' • ${percent(knownTotal: knownTotal)}%';
  }

  /// Remaining line, e.g. `12.7 MB remaining`, or null while the total
  /// is unknown.
  String? remainingLine({int? knownTotal}) {
    final int t = effectiveTotal(knownTotal);
    if (t <= 0) return null;
    return '${formatMegabytes(remainingBytes(knownTotal: knownTotal))}'
        ' MB remaining';
  }
}

/// Global update-download state (Jaani, 3 Nov 2026). Lives outside any
/// widget so the download survives navigation and rebuilds.
class UpdateDownloadState {
  UpdateDownloadState._();

  static final UpdateDownloadState instance = UpdateDownloadState._();

  /// Live progress; the banner listens to this.
  final ValueNotifier<DownloadProgress> progress =
      ValueNotifier<DownloadProgress>(
    const DownloadProgress(downloaded: 0, total: 0, stalled: false),
  );

  /// Android DownloadManager id of the in-flight download, null when
  /// idle. Persisted in SharedPreferences for cold-start re-attach.
  int? downloadId;

  /// Version info of the in-flight download (for the install dialog).
  int? versionCode;
  String? versionName;
  String? notes;

  /// Known APK size in bytes (HTTP Content-Length, fetched before the
  /// download starts) — the fallback total when DownloadManager reports
  /// the total as unknown (-1). Persisted with the download id for
  /// cold-start re-attach.
  int? knownTotalBytes;

  bool get isActive => downloadId != null;

  void reset() {
    downloadId = null;
    versionCode = null;
    versionName = null;
    notes = null;
    knownTotalBytes = null;
    progress.value = const DownloadProgress(
      downloaded: 0,
      total: 0,
      stalled: false,
    );
  }
}

/// Shared live progress view (Jaani, 18 Nov 2026): the progress bar,
/// the `downloaded / total MB • %` line and the `MB remaining` line.
/// Used by BOTH the bottom banner and the update progress dialog, so
/// the two can never disagree — they render the same notifier through
/// this one widget. [knownTotal] is the APK Content-Length fallback
/// for when DownloadManager reports the total as unknown; it is fixed
/// before the banner/dialog are shown, so a plain value (not a
/// notifier) is enough.
class DownloadProgressView extends StatelessWidget {
  final ValueNotifier<DownloadProgress> progress;
  final int? knownTotal;
  final String? stalledText;

  const DownloadProgressView({
    super.key,
    required this.progress,
    this.knownTotal,
    this.stalledText,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DownloadProgress>(
      valueListenable: progress,
      builder: (BuildContext ctx, DownloadProgress p, Widget? _) {
        final String? remaining = p.remainingLine(knownTotal: knownTotal);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(value: p.fraction(knownTotal: knownTotal)),
            const SizedBox(height: 8.0),
            Text(p.mainLine(knownTotal: knownTotal)),
            if (remaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(remaining),
              ),
            if (p.stalled && stalledText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  stalledText!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Non-blocking download progress banner (Jaani, 2 Nov 2026): sits at
/// the bottom of the screen while the APK downloads in the background —
/// the app is never locked behind a modal dialog. Inserted through the
/// global navigator's overlay, so it persists across screens.
class _DownloadProgressBanner extends StatelessWidget {
  final ValueNotifier<DownloadProgress> progress;
  final AppLocalizations? localizations;

  const _DownloadProgressBanner({
    required this.progress,
    required this.localizations,
  });

  @override
  Widget build(BuildContext context) {
    final t = localizations;
    final title = t?.downloading ?? 'Downloading update…';
    final stalledText =
        t?.downloadStalled ?? 'Stalled — check your connection';
    return Positioned(
      left: 16.0,
      right: 16.0,
      bottom: 32.0,
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8.0),
              DownloadProgressView(
                progress: progress,
                // Set before the banner is shown (download start or
                // cold-start restore); see UpdateDownloadState.
                knownTotal: UpdateDownloadState.instance.knownTotalBytes,
                stalledText: stalledText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdaterService {
  static const _channel = MethodChannel('tj_earn/updater');

  /// SharedPreferences keys for cold-start re-attach of an in-flight
  /// DownloadManager download.
  static const _prefsIdKey = 'tj_earn_update_download_id';
  static const _prefsCodeKey = 'tj_earn_update_version_code';
  static const _prefsNameKey = 'tj_earn_update_version_name';
  static const _prefsNotesKey = 'tj_earn_update_notes';
  static const _prefsTotalKey = 'tj_earn_update_total_bytes';

  /// Website manifest (Doner-style, Jaani 3 Nov 2026). Published by the
  /// parent with the stable APK download link; the Supabase app_versions
  /// table is stale and must NOT be used.
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
        // Optional APK size in bytes (manifest-pinned fallback total
        // when DownloadManager reports the total as unknown).
        'size': (data['size'] as int?) ?? (data['sizeBytes'] as int?),
      };
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Fetches the APK size (HTTP Content-Length) with a HEAD request.
  /// Used as the fallback total when DownloadManager reports the total
  /// as unknown (-1). Returns null on ANY failure (no network, no
  /// Content-Length, redirect trouble). Never throws; a missing size
  /// only means percent/remaining stay hidden, never a broken update.
  static Future<int?> _fetchApkSize(String apkUrl) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.headUrl(Uri.parse(apkUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>().timeout(const Duration(seconds: 5));
      final length = response.headers.contentLength;
      return length > 0 ? length : null;
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
      // Best-effort.
    }
  }

  static OverlayEntry? _banner;

  /// Poll-loop generation (Jaani, 18 Nov 2026). The old `bool _polling`
  /// guard could strand a download with NO poll loop: if a loop was
  /// still alive for a previous (stale) download id when a new download
  /// started, the new poll returned immediately and the old loop kept
  /// polling the id it started with. Every download start now bumps
  /// the epoch; a loop exits as soon as its epoch is superseded, and a
  /// fresh loop always starts for the new download.
  static int _pollEpoch = 0;

  /// Cold-start re-attach (Jaani, 3 Nov 2026): called once after the
  /// first frame. If a previous session left a download in-flight, the
  /// banner + polling are restored; if it already finished, the install
  /// prompt is shown. Never throws, never blocks startup.
  static Future<void> restoreDownloadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_prefsIdKey);
      if (id == null) return;
      final state = UpdateDownloadState.instance;
      state.downloadId = id;
      state.versionCode = prefs.getInt(_prefsCodeKey);
      state.versionName = prefs.getString(_prefsNameKey);
      state.notes = prefs.getString(_prefsNotesKey);
      state.knownTotalBytes = prefs.getInt(_prefsTotalKey);
      final st = await _downloadStatus(id);
      final s = st['status'] as String?;
      if (s == 'running' || s == 'pending' || s == 'paused') {
        _showBanner();
        unawaited(_pollLoop());
        return;
      }
      if (s == 'success') {
        await _onDownloadSuccess(st);
        return;
      }
      // failed / not_found / unknown -> drop the stale record.
      await _clearSavedState();
      state.reset();
    } catch (_) {
      // Restore must never break startup.
    }
  }

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
      await _downloadAndInstall(
        context,
        apkUrl,
        versionCode: latestCode,
        versionName: latest['versionName'] as String?,
        notes: latest['notes'] as String?,
        knownTotalBytes: latest['size'] as int?,
      );
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
    await _downloadAndInstall(
      context,
      apkUrl,
      versionCode: latestCode,
      versionName: latest['versionName'] as String?,
      notes: latest['notes'] as String?,
      knownTotalBytes: latest['size'] as int?,
    );
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

  /// Download via Android DownloadManager (system process — survives app
  /// background/kill, shows a notification with progress, auto-resumes
  /// on network interruption, follows redirects natively). The banner
  /// and poll loop are GLOBAL ([UpdateDownloadState]), so the user can
  /// navigate away mid-download; the install prompt is shown through
  /// the global navigator when the APK is ready.
  static Future<void> _downloadAndInstall(
    BuildContext context,
    String apkUrl, {
    int? versionCode,
    String? versionName,
    String? notes,
    int? knownTotalBytes,
  }) async {
    final localizations = AppLocalizations.of(context);
    final isUrdu = localizations?.localeName == 'ur';
    // Capture UI strings BEFORE any async gap (analyzer:
    // use_build_context_synchronously) — only plain strings may cross
    // awaits; BuildContexts never do.
    final String permissionMessage =
        localizations?.installPermissionNeeded ??
            'Allow install permission in Settings, then try again.';
    final String errorMessage =
        localizations?.genericError ?? 'Something went wrong. Please try again.';
    bool canInstall = true;
    try {
      canInstall =
          await _channel.invokeMethod<bool>('canInstallPackages').timeout(
                const Duration(seconds: 10),
              ) ??
              true;
    } catch (_) {
      // A channel hiccup must not block the update; the system install
      // UI surfaces the permission itself when needed.
      canInstall = true;
    }
    if (!canInstall) {
      try {
        await _channel.invokeMethod<void>('openInstallSettings');
      } catch (_) {
        // Best-effort.
      }
      _globalSnack(permissionMessage);
      return;
    }
    final state = UpdateDownloadState.instance;
    if (state.isActive) return; // a download is already running
    // Known APK size for live percent/remaining when DownloadManager
    // reports the total as unknown (-1): manifest size first, else a
    // HEAD Content-Length lookup. Fail-soft — a missing size only hides
    // the percent, never blocks the download.
    final int? knownTotal =
        (knownTotalBytes != null && knownTotalBytes > 0)
            ? knownTotalBytes
            : await _fetchApkSize(apkUrl);
    state.knownTotalBytes = knownTotal;
    int? downloadId;
    try {
      downloadId = await _channel.invokeMethod<int>(
        'downloadApk',
        {'url': apkUrl, 'fileName': 'tj-earn-update.apk'},
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      downloadId = null;
    }
    if (downloadId == null) {
      state.knownTotalBytes = null;
      _globalSnack(errorMessage);
      return;
    }
    state.downloadId = downloadId;
    state.versionCode = versionCode;
    state.versionName = versionName;
    state.notes = notes;
    state.progress.value = const DownloadProgress(
      downloaded: 0,
      total: 0,
      stalled: false,
    );
    await _saveState();
    _showBanner();
    _showProgressDialog(versionName: versionName);
    _globalSnack(
      isUrdu
          ? 'اپ ڈیٹ بیک گراؤنڈ میں ڈاؤن لوڈ ہو رہی ہے — آپ ایپ استعمال کرتے رہیں۔'
          : 'Update is downloading in the background — keep using the app.',
    );
    // Fire-and-forget: the system download survives app background/kill
    // regardless of this loop; the banner updates live and the install
    // prompt fires on completion.
    unawaited(_pollLoop());
  }

  /// Global poll loop: one live loop per download generation
  /// ([_pollEpoch]). Drives [UpdateDownloadState.progress] with REAL
  /// numbers from DownloadManager; on completion the install prompt is
  /// shown through the global navigator.
  ///
  /// ROOT-CAUSE NOTE (Jaani, 18 Nov 2026): the old loop could NEVER
  /// deliver a single update. Dart sends the download id as a 32-bit
  /// int; the Kotlin side read it with `call.argument<Long>`, which
  /// throws (Integer cannot be cast to Long — Kotlin has no implicit
  /// Int→Long conversion) on EVERY call, so `downloadStatus` always
  /// answered QUERY_FAILED, the loop swallowed it with `continue`,
  /// and the banner sat at its initial `0.0 / 0.0 MB • 0%` while
  /// DownloadManager finished the download and the native receiver
  /// fired the installer on its own. Fixed in MainActivity.kt
  /// (accept any Number id) — and this loop no longer hides a broken
  /// channel: a status failure still keeps polling (the system
  /// download runs regardless), but the loop now (a) polls
  /// immediately instead of waiting 2s for the first sample, (b)
  /// substitutes the known APK size when the reported total is
  /// unknown (-1), and (c) can never be stranded by a stale guard.
  static Future<void> _pollLoop() async {
    final int epoch = ++_pollEpoch;
    final state = UpdateDownloadState.instance;
    int lastBytes = 0;
    DateTime lastChange = DateTime.now();
    // Poll DownloadManager for completion (max ~10 minutes).
    for (var i = 0; i < 300; i++) {
      if (epoch != _pollEpoch) return; // superseded by a newer download
      final id = state.downloadId;
      if (id == null) break;
      // First sample immediately — a fast download must not go
      // unobserved for 2s; later samples every 2s.
      if (i > 0) await Future.delayed(const Duration(seconds: 2));
      if (epoch != _pollEpoch) return;
      if (state.downloadId != id) continue; // id changed; re-read it
      late final Map<String, dynamic> st;
      try {
        st = await _downloadStatus(id);
      } catch (_) {
        // Channel hiccup (or a broken native side): keep polling —
        // the system download runs regardless, and the native
        // receiver + cold-start re-attach remain as fallbacks.
        continue;
      }
      final s = st['status'] as String?;
      final int downloaded = (st['bytesDownloaded'] as num?)?.toInt() ?? 0;
      final int rawTotal = (st['bytesTotal'] as num?)?.toInt() ?? 0;
      // -1/0 total = unknown: substitute the known APK size so the
      // percent, total and remaining are real numbers, not 0%.
      final int total = resolveDownloadTotal(
        reportedTotal: rawTotal,
        knownTotal: state.knownTotalBytes,
      );
      final DateTime now = DateTime.now();
      if (downloaded > lastBytes) {
        lastBytes = downloaded;
        lastChange = now;
      }
      final bool stalled = (s == 'running' || s == 'pending') &&
          now.difference(lastChange).inSeconds >= 60;
      state.progress.value = DownloadProgress(
        downloaded: downloaded < 0 ? 0 : downloaded,
        total: total,
        stalled: stalled,
      );
      if (s == 'success') {
        await _onDownloadSuccess(st);
        return;
      } else if (s == 'failed' || s == 'not_found') {
        await _onDownloadFailed();
        return;
      }
      // running/pending/paused/unknown -> keep polling; banner and
      // progress dialog show live progress.
    }
    // Poll window exhausted (very slow network): hide the banner and
    // the progress dialog but leave the system download running — its
    // notification keeps the user informed, and the next cold start
    // re-attaches automatically.
    if (state.downloadId != null) {
      _hideBanner();
      _hideProgressDialog();
    }
  }

  static Future<void> _onDownloadSuccess(Map<String, dynamic> st) async {
    final state = UpdateDownloadState.instance;
    final vName = state.versionName;
    final vNotes = state.notes;
    final vCode = state.versionCode;
    _hideBanner();
    _hideProgressDialog();
    state.reset();
    await _clearSavedState();
    // Don't prompt when the newer build is already installed (e.g. the
    // native download-complete receiver fired while the app was dead
    // and the user already installed).
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;
      if (vCode != null && installed >= vCode) return;
    } catch (_) {
      // Fall through and show the prompt.
    }
    final path = _uriToPath(st['localUri'] as String? ?? '');
    if (path == null) return;
    _showInstallDialog(path, vName, vNotes);
  }

  static Future<void> _onDownloadFailed() async {
    // Capture the message before the async gap (analyzer:
    // use_build_context_synchronously); only a plain string crosses it.
    final ctx = appNavigatorKey.currentContext;
    final String message =
        (ctx == null ? null : AppLocalizations.of(ctx)?.genericError) ??
            'Something went wrong. Please try again.';
    final state = UpdateDownloadState.instance;
    _hideBanner();
    _hideProgressDialog();
    state.reset();
    await _clearSavedState();
    _globalSnack(message);
  }

  /// Install prompt through the GLOBAL navigator (Jaani, 3 Nov 2026):
  /// appears even if the user navigated away from Settings.
  static void _showInstallDialog(
    String apkPath,
    String? versionName,
    String? notes,
  ) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return; // next cold start will offer it again
    final t = AppLocalizations.of(ctx);
    final isUrdu = t?.localeName == 'ur';
    showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t?.updateAvailable ?? 'Update available'),
        content: Text(
          [
            if (versionName != null && versionName.isNotEmpty) versionName,
            if (notes != null && notes.isNotEmpty) notes,
            isUrdu
                ? 'اپ ڈیٹ ڈاؤن لوڈ ہو چکا ہے۔ انسٹال مکمل کرنے کے لیے انسٹال دبائیں۔'
                : 'The update has finished downloading. Tap Install to complete the update.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(t?.updateLater ?? 'Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              unawaited(
                _channel
                    .invokeMethod<void>('installApk', {'path': apkPath})
                    .timeout(const Duration(seconds: 10))
                    .catchError((_) {}),
              );
            },
            child: Text(isUrdu ? 'انسٹال کریں' : 'Install'),
          ),
        ],
      ),
    );
  }

  /// Shows a snackbar through the global navigator. Sync — grabs the
  /// current context fresh, so no BuildContext ever crosses an async gap
  /// (analyzer: use_build_context_synchronously).
  static void _globalSnack(String message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Inserts the progress banner into the GLOBAL navigator's overlay
  /// (survives navigation). No-op when already inserted or when the
  /// overlay isn't ready yet.
  static void _showBanner() {
    if (_banner != null) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    final ctx = appNavigatorKey.currentContext;
    final t = ctx == null ? null : AppLocalizations.of(ctx);
    _banner = OverlayEntry(
      builder: (_) => _DownloadProgressBanner(
        progress: UpdateDownloadState.instance.progress,
        localizations: t,
      ),
    );
    overlay.insert(_banner!);
  }

  static void _hideBanner() {
    _banner?.remove();
    _banner = null;
  }

  /// The live update progress dialog (Jaani, 18 Nov 2026): shown when
  /// a download starts, it renders the SAME [DownloadProgressView] as
  /// the banner — percent 0–100, MB downloaded, total MB and MB
  /// remaining, updating live from [UpdateDownloadState.progress].
  /// "Hide" (or tapping outside) dismisses the dialog; the banner
  /// keeps showing the same live numbers underneath.
  static bool _progressDialogOpen = false;
  static BuildContext? _progressDialogContext;

  static void _showProgressDialog({String? versionName}) {
    if (_progressDialogOpen) return;
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return; // banner still shows progress
    final t = AppLocalizations.of(ctx);
    final isUrdu = t?.localeName == 'ur';
    final title = t?.downloading ?? 'Downloading update…';
    final stalledText =
        t?.downloadStalled ?? 'Stalled — check your connection';
    final hideLabel = isUrdu ? 'چھپائیں' : 'Hide';
    _progressDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: ctx,
        barrierDismissible: true,
        builder: (dialogCtx) {
          _progressDialogContext = dialogCtx;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (versionName != null && versionName.isNotEmpty) ...<Widget>[
                  Text(
                    versionName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12.0),
                ],
                DownloadProgressView(
                  progress: UpdateDownloadState.instance.progress,
                  knownTotal: UpdateDownloadState.instance.knownTotalBytes,
                  stalledText: stalledText,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(hideLabel),
              ),
            ],
          );
        },
      ).then((_) {
        _progressDialogOpen = false;
        _progressDialogContext = null;
      }),
    );
  }

  /// Dismisses the progress dialog if it is open (success, failure, or
  /// poll-window exhaustion). No-op otherwise; never throws.
  static void _hideProgressDialog() {
    if (!_progressDialogOpen) return;
    final dialogCtx = _progressDialogContext;
    if (dialogCtx == null) return;
    try {
      Navigator.of(dialogCtx).pop();
    } catch (_) {
      // Dialog already gone; the .then() above clears the flag.
    }
  }

  static Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = UpdateDownloadState.instance;
      final id = state.downloadId;
      if (id == null) return;
      await prefs.setInt(_prefsIdKey, id);
      final code = state.versionCode;
      if (code != null) await prefs.setInt(_prefsCodeKey, code);
      final name = state.versionName;
      if (name != null) await prefs.setString(_prefsNameKey, name);
      final n = state.notes;
      if (n != null) await prefs.setString(_prefsNotesKey, n);
      final total = state.knownTotalBytes;
      if (total != null) await prefs.setInt(_prefsTotalKey, total);
    } catch (_) {
      // Best-effort: without the record the download still completes
      // in DownloadManager; only the re-attach is lost.
    }
  }
    

  
  static Future<void> _clearSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsIdKey);
      await prefs.remove(_prefsCodeKey);
      await prefs.remove(_prefsNameKey);
      await prefs.remove(_prefsNotesKey);
      await prefs.remove(_prefsTotalKey);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Queries DownloadManager for one download id. Throws on channel
  /// failure (callers decide whether to retry or abort).
  static Future<Map<String, dynamic>> _downloadStatus(int downloadId) async {
    final res = await _channel
        .invokeMethod<Map>('downloadStatus', {'downloadId': downloadId})
        .timeout(const Duration(seconds: 10));
    return Map<String, dynamic>.from(res ?? <String, dynamic>{});
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
