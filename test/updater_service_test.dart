import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_earn/services/updater_service.dart';

// TJ Earn v1.0.29: live update-progress reporting.
//
// Covers the pure, device-free parts of the fix:
//  - total resolution (DownloadManager -1/0 -> Content-Length fallback)
//  - percent / fraction / MB / remaining math on DownloadProgress
//  - the exact lines the banner AND the progress dialog render
//  - the shared DownloadProgressView widget reacting live to the
//    progress notifier (this is the same widget both surfaces use)
//
// NOT covered here (needs a device): the Kotlin downloadStatus
// channel (MethodChannel int/long handling), a real DownloadManager
// download end-to-end, the install prompt, and the poll loop timing.
// Those are verified by the local debug build + on-device testing.

void main() {
  group('resolveDownloadTotal', () {
    test('reported total wins when known', () {
      expect(
        resolveDownloadTotal(reportedTotal: 25000000, knownTotal: 26000000),
        25000000,
      );
    });

    test('unknown reported total (-1) falls back to the known APK size',
        () {
      expect(
        resolveDownloadTotal(reportedTotal: -1, knownTotal: 26000000),
        26000000,
      );
    });

    test('zero reported total falls back to the known APK size', () {
      expect(
        resolveDownloadTotal(reportedTotal: 0, knownTotal: 26000000),
        26000000,
      );
    });

    test('unknown everywhere resolves to 0 (unknown)', () {
      expect(resolveDownloadTotal(reportedTotal: -1, knownTotal: null), 0);
      expect(resolveDownloadTotal(reportedTotal: 0, knownTotal: 0), 0);
      expect(resolveDownloadTotal(reportedTotal: -1, knownTotal: -5), 0);
    });
  });

  group('DownloadProgress math', () {
    const int total = 20 * 1024 * 1024; // 20.0 MB
    const int half = 10 * 1024 * 1024; // 10.0 MB

    test('percent 0-100 from downloaded/total', () {
      const p = DownloadProgress(
        downloaded: half,
        total: total,
        stalled: false,
      );
      expect(p.percent(), 50);
      expect(p.fraction(), 0.5);
      expect(p.remainingBytes(), half);
    });

    test('percent clamps above 100 and below 0', () {
      const over = DownloadProgress(
        downloaded: total + 1,
        total: total,
        stalled: false,
      );
      expect(over.percent(), 100);
      expect(over.fraction(), 1.0);
      expect(over.remainingBytes(), 0);
    });

    test('unknown total: percent 0, no fraction, no remaining', () {
      const p = DownloadProgress(
        downloaded: half,
        total: -1,
        stalled: false,
      );
      expect(p.percent(), 0);
      expect(p.fraction(), isNull);
      expect(p.remainingBytes(), 0);
    });

    test('unknown reported total uses the known APK size', () {
      const p = DownloadProgress(
        downloaded: half,
        total: -1,
        stalled: false,
      );
      expect(p.percent(knownTotal: total), 50);
      expect(p.fraction(knownTotal: total), 0.5);
      expect(p.remainingBytes(knownTotal: total), half);
    });

    test('zero progress at the start', () {
      const p = DownloadProgress(downloaded: 0, total: 0, stalled: false);
      expect(p.percent(), 0);
      expect(p.fraction(), isNull);
      expect(p.remainingBytes(), 0);
    });
  });

  group('DownloadProgress display lines', () {
    test('main line shows downloaded / total MB and percent', () {
      const p = DownloadProgress(
        downloaded: 5 * 1024 * 1024,
        total: 20 * 1024 * 1024,
        stalled: false,
      );
      expect(p.mainLine(), '5.0 / 20.0 MB • 25%');
      expect(p.remainingLine(), '15.0 MB remaining');
    });

    test('main line shows downloaded only while the total is unknown',
        () {
      const p = DownloadProgress(
        downloaded: 5 * 1024 * 1024,
        total: -1,
        stalled: false,
      );
      expect(p.mainLine(), '5.0 MB downloaded');
      expect(p.remainingLine(), isNull);
    });

    test('main line uses the known APK size when the total is unknown',
        () {
      const p = DownloadProgress(
        downloaded: 5 * 1024 * 1024,
        total: -1,
        stalled: false,
      );
      expect(
        p.mainLine(knownTotal: 20 * 1024 * 1024),
        '5.0 / 20.0 MB • 25%',
      );
      expect(
        p.remainingLine(knownTotal: 20 * 1024 * 1024),
        '15.0 MB remaining',
      );
    });

    test('formatMegabytes rounds to one decimal', () {
      expect(formatMegabytes(0), '0.0');
      expect(formatMegabytes(1048576), '1.0');
      expect(formatMegabytes(1572864), '1.5');
      expect(formatMegabytes(26214400), '25.0');
    });
  });

  group('UpdateDownloadState', () {
    test('reset clears the known total as well as the id', () {
      final state = UpdateDownloadState.instance;
      state.downloadId = 7;
      state.knownTotalBytes = 25000000;
      state.versionName = '1.0.29';
      state.reset();
      expect(state.downloadId, isNull);
      expect(state.knownTotalBytes, isNull);
      expect(state.versionName, isNull);
      expect(state.isActive, isFalse);
      expect(state.progress.value.downloaded, 0);
      expect(state.progress.value.total, 0);
    });
  });

  group('DownloadProgressView widget (banner + dialog shared view)', () {
    Future<void> pumpView(
      WidgetTester tester,
      ValueNotifier<DownloadProgress> progress, {
      int? knownTotal,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadProgressView(
              progress: progress,
              knownTotal: knownTotal,
              stalledText: 'Stalled — check your connection',
            ),
          ),
        ),
      );
    }

    testWidgets('shows live percent, MB and remaining as progress moves',
        (tester) async {
      final progress = ValueNotifier<DownloadProgress>(
        const DownloadProgress(downloaded: 0, total: 0, stalled: false),
      );
      addTearDown(progress.dispose);
      await pumpView(
        tester,
        progress,
        knownTotal: 20 * 1024 * 1024,
      );
      expect(find.text('0.0 / 20.0 MB • 0%'), findsOneWidget);
      expect(find.text('20.0 MB remaining'), findsOneWidget);

      progress.value = const DownloadProgress(
        downloaded: 10 * 1024 * 1024,
        total: -1,
        stalled: false,
      );
      await tester.pump();
      // Same widget, same numbers the dialog shows: total fell back
      // to the known APK size.
      expect(find.text('10.0 / 20.0 MB • 50%'), findsOneWidget);
      expect(find.text('10.0 MB remaining'), findsOneWidget);

      progress.value = const DownloadProgress(
        downloaded: 20 * 1024 * 1024,
        total: 20 * 1024 * 1024,
        stalled: false,
      );
      await tester.pump();
      expect(find.text('20.0 / 20.0 MB • 100%'), findsOneWidget);
      expect(find.text('0.0 MB remaining'), findsOneWidget);
    });

    testWidgets('shows downloaded MB only while the total is unknown',
        (tester) async {
      final progress = ValueNotifier<DownloadProgress>(
        const DownloadProgress(
          downloaded: 5 * 1024 * 1024,
          total: -1,
          stalled: false,
        ),
      );
      addTearDown(progress.dispose);
      await pumpView(tester, progress);
      expect(find.text('5.0 MB downloaded'), findsOneWidget);
      expect(find.textContaining('MB remaining'), findsNothing);
    });

    testWidgets('shows the stalled warning when flagged', (tester) async {
      final progress = ValueNotifier<DownloadProgress>(
        const DownloadProgress(
          downloaded: 1024,
          total: 20 * 1024 * 1024,
          stalled: true,
        ),
      );
      addTearDown(progress.dispose);
      await pumpView(tester, progress);
      expect(
        find.text('Stalled — check your connection'),
        findsOneWidget,
      );
    });
  });
}
