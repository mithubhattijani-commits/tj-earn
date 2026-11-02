import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'services/admin_status.dart';
import 'services/device_service.dart';
import 'services/remote_config_service.dart';
import 'services/supabase_service.dart';
import 'services/unity_ads_service.dart';
import 'theme.dart';

/// Language choice, persisted locally. Defaults to English.
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  if (saved == 'ur') appLocale.value = const Locale('ur');

  // ROOT-CAUSE FIX (Jaani, 2 Nov 2026): runApp is called IMMEDIATELY.
  // Nothing network-related runs before the first frame anymore — the
  // old code awaited SupabaseService.init() here, and a stalled network
  // hung the app on a black screen until Android raised ANR. Supabase
  // init now happens inside _BootGate with a hard 15s timeout.

  // Remote Config (Jaani, 2 Nov 2026): fire-and-forget, NOT awaited.
  // init() loads the local cache (fast) and refreshes from the network
  // in the background with an 8s timeout — nothing here may block the
  // first frame (APP ROBUSTNESS RULE).
  unawaited(RemoteConfigService.instance.init());

  runApp(TjEarnApp(prefs: prefs));
}

class TjEarnApp extends StatefulWidget {
  final SharedPreferences prefs;

  const TjEarnApp({super.key, required this.prefs});

  @override
  State<TjEarnApp> createState() => _TjEarnAppState();
}

class _TjEarnAppState extends State<TjEarnApp> {
  late Future<bool> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _bootApp();
  }

  /// Boots the backend connection. Returns true when Supabase is
  /// configured AND initialized. Never throws and never hangs:
  /// [SupabaseService.init] has a 15s hard timeout.
  Future<bool> _bootApp() async {
    if (!AppConfig.isConfigured) return false;
    try {
      await SupabaseService.init();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _retryBoot() {
    setState(() {
      _boot = _bootApp();
    });
  }

  Future<void> _changeLocale(Locale locale) async {
    appLocale.value = locale;
    await widget.prefs.setString('language', locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'TJ Earn',
          locale: locale,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: TjEarnTheme.dark,
          home: FutureBuilder<bool>(
            future: _boot,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                // Brief local-only loading; never a network wait.
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data == true) {
                // Unity Ads init is best-effort and never blocks startup:
                // the Watch Ad screen re-tries a late init and explains
                // when ads are unavailable.
                // Dual-ad system (Jaani, 2 Nov 2026): after init, show the
                // App Open ad once per cold start (fire-and-forget, 8s max).
                // ignore: unawaited_futures
                UnityAdsService.init().then((_) {
                  // ignore: unawaited_futures
                  UnityAdsService.showAppOpenAd();
                });
                return AuthGate(onLocaleChanged: _changeLocale);
              }
              return ConfigErrorScreen(onRetry: _retryBoot);
            },
          ),
        );
      },
    );
  }
}

/// Shown when Supabase is not configured (or init failed / timed out).
/// The app never shows a fake balance or a fake logged-in state in this
/// condition. A retry button re-runs the bounded boot.
class ConfigErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const ConfigErrorScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TJ Earn')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Connection failed',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not reach the TJ Earn server. Check your internet '
              'connection and try again. No balance is shown until the '
              'connection works.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  final void Function(Locale locale) onLocaleChanged;

  const AuthGate({super.key, required this.onLocaleChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) {
          AdminStatus.reset();
          return const AuthScreen();
        }
        AdminStatus.probe();
        // Register device for anti-fraud (silent, never blocks).
        // ignore: unawaited_futures
        DeviceService.register();
        return MainShell(
          locale: appLocale.value,
          onLocaleChanged: onLocaleChanged,
        );
      },
    );
  }
}
