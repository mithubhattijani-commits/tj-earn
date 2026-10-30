import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'services/admin_status.dart';
import 'services/supabase_service.dart';
import 'services/unity_ads_service.dart';

/// Language choice, persisted locally. Defaults to English.
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  if (saved == 'ur') appLocale.value = const Locale('ur');

  var initFailed = false;
  if (AppConfig.isConfigured) {
    try {
      await SupabaseService.init();
    } catch (_) {
      initFailed = true;
    }
    // Unity Ads init is best-effort and never blocks startup: the Offers
    // tab re-tries a late init and explains when ads are unavailable.
    // ignore: unawaited_futures
    UnityAdsService.init();
  }

  runApp(TjEarnApp(
    configured: AppConfig.isConfigured && !initFailed,
    prefs: prefs,
  ));
}

class TjEarnApp extends StatelessWidget {
  final bool configured;
  final SharedPreferences prefs;

  const TjEarnApp({super.key, required this.configured, required this.prefs});

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
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          home: configured
              ? AuthGate(onLocaleChanged: _changeLocale)
              : const ConfigErrorScreen(),
        );
      },
    );
  }

  Future<void> _changeLocale(Locale locale) async {
    appLocale.value = locale;
    await prefs.setString('language', locale.languageCode);
  }
}

/// Shown when Supabase is not configured (or init failed). The app never
/// shows a fake balance or a fake logged-in state in this condition.
class ConfigErrorScreen extends StatelessWidget {
  const ConfigErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TJ Earn')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'App not configured',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Supabase is not configured for this build. Set SUPABASE_URL '
              'and SUPABASE_ANON_KEY with --dart-define and rebuild. '
              'No balance is shown until then.',
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
        return MainShell(
          locale: appLocale.value,
          onLocaleChanged: onLocaleChanged,
        );
      },
    );
  }
}
