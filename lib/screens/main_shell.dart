import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/startup_bundle_service.dart';
import '../services/supabase_service.dart';
import 'watch_ad_screen.dart';

/// Minimal Watch-Ads-only shell (Jaani, 3 Nov 2026).
///
/// The full multi-tab app was ANR'ing. This stripped version keeps ONLY:
/// - Balance display (from Supabase, with cached fallback)
/// - Watch Ad button (Unity rewarded → coins via claim-unity-reward)
///
/// No tabs, no navigation, no referral/wallet/withdraw/settings.
/// Website (nigraantv.xyz/earn/) handles everything else.
class MainShell extends StatefulWidget {
  final Locale locale;
  final void Function(Locale locale) onLocaleChanged;

  const MainShell({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late Future<int> _balance;

  @override
  void initState() {
    super.initState();
    _balance = _loadBalance();
  }

  Future<int> _loadBalance() async {
    try {
      return await SupabaseService.getBalance();
    } catch (_) {
      return StartupBundleService.balanceCoins;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      t.balance,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<int>(
                      future: _balance,
                      builder: (context, snapshot) {
                        final coins = snapshot.data ??
                            StartupBundleService.balanceCoins;
                        return Text(
                          '$coins',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                    Text(
                      t.coins,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WatchAdScreen(),
                  ),
                ).then((_) {
                  // Refresh balance after returning from Watch Ad
                  if (mounted) {
                    setState(() {
                      _balance = _loadBalance();
                    });
                  }
                });
              },
              icon: const Icon(Icons.play_circle_outline),
              label: Text(t.watchAdTile),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
