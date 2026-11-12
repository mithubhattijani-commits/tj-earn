import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_navigator.dart';
import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'services/admin_status.dart';
import 'services/startup_bundle_service.dart';
import 'services/device_service.dart';
import 'services/referral_deep_link_service.dart';
import 'services/remote_config_service.dart';
import 'services/supabase_service.dart';
import 'services/unity_ads_service.dart';
import 'services/updater_service.dart';
import 'theme.dart';

/// Language choice, persisted locally. Default language is English
/// (Task D, 12 Nov 2026); Urdu is second — it applies only when the
/// user previously chose it. Any other or missing saved value falls
/// back to English.
final ValueNotifier<Locale> appLocale =
    ValueNotifier(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  // Default language is English: only a saved 'ur' switches to Urdu.
  appLocale.value =
      saved == 'ur' ? const Locale('ur') : const Locale('en');

  // ROOT-CAUSE FIX (Jaani, 2 Nov 2026): runApp is called IMMEDIATELY.
  // Nothing network-related runs before the first frame anymore — the
  // old code awaited SupabaseService.init() here, and a stalled network
  // hung the app on a black screen until Android raised ANR. Supabase
  // init now happens inside _BootGate with a hard 15s timeout.
  runApp(
    ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) => _TjEarnApp(locale: locale),
    ),
  );

  // Leave no trace of the unmounted webview's resources when the app
  // is terminated: stop the ad callbacks.
  // Remote Config init (v1, 10 Nov 2026; polling per Task D, 12 Nov 2026):
  // loads the local cache (fast), then fetches fresh from the network
  // in the background with an 8s timeout, and polls every ~60s — nothing
  // here may block the first frame.
  unawaited(RemoteConfigService.instance.init());

  // Startup bundle: fire-and-forget snapshot fetch. It is the only
  // network call in main() that touches the first paint.
  // It must be monitored by the DIAGNOSTIC MODE check in _BootGate.
  unawaited(StartupBundleService.fetch());

  // Referral deep link bootstrap (Jaani, 3 Nov 2026): capture a
  // referral code passed in the launch Intent (?ref=CODE), or if the app
  // was already running, handle the link when it arrives. Stored as
  // pending and auto-applied after the user signs in.
  // Both calls are fire-and-forget and never block the first frame.
  try {
    await ReferralDeepLinkService.init();
    unawaited(ReferralDeepLinkService.startListening());
  } catch (_) {
    // Deep-link bootstrap must never block startup.
  }

  // Update check's own restore: restarts an interrupted download with
  // the same consistent state it was in, and shows a Continue snackbar
  // at the top. Async void, safe because it never throws.
  unawaited(UpdaterService.restoreDownloadState());

  // Unity Ads: fire-and-forget init in the background.
  // Never touches the first frame.
  unawaited(UnityAdsService.init());
}

/// The root of the app.
class _TjEarnApp extends StatefulWidget {
  final Locale locale;
  const _TjEarnApp({required this.locale});

  @override
  State<_TjEarnApp> createState() => _TjEarnAppState();
}

class _TjEarnAppState extends State<_TjEarnApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TJ Earn',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      locale: widget.locale,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _BootGate(),
    );
  }
}

/// The boot gate: decides which screen is shown.
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  /// Hard 15s boot timeout: if Supabase doesn't answer quickly, the app
  /// falls back to the auth screen instead of a black screen.
  static const Duration bootTimeout = Duration(seconds: 15);

  bool _ready = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _initSupabase();
  }

  /// First frame first: waits for Supabase, and updates the root's
  /// navigation logic.
  Future<void> _initSupabase() async {
    try {
      await SupabaseService.init()
          .timeout(bootTimeout)
          .catchError((e) => debugPrint('Supabase init error: $e'));
      if (!mounted) return;
      setState(() {
        _signedIn = SupabaseService.isSignedIn;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      // Reason: Supabase took too long to respond OR threw an error.
      // We still show the auth screen instead of a black screen.
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _signedIn
        ? MainShell(locale: widgetLocale, onLocaleChanged: _changeLocale)
        : const AuthScreen();
  }

  Locale get widgetLocale => appLocale.value;

  /// Language changes come from the Settings tab: the dropdown
  /// updates [appLocale], which rebuilds _TjEarnApp. This callback is
  /// still needed because MainShell only holds the locale for itself.
  void _changeLocale(Locale locale) {
    appLocale.value = locale;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('language', locale.languageCode),
      ),
    );
  }
}
