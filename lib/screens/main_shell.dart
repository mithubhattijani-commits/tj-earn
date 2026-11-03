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
///
/// Daily upgrade, 3 Nov 2026 (Shami): fixed the `int?`-into-`Future<int>`
/// analyzer error that broke CI on the minimal-shell rewrite; added the
/// Rs-equivalent line under the balance (restores the pre-cut UX) and
/// pull-to-refresh on the balance card (flaky-network recovery without
/// an app restart).
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
      // FIX (3 Nov 2026): balanceCoins is nullable — the old code returned
      // `int?` from a `Future<int>` method and broke `flutter analyze`
      // (CI red). Fall back to 0 when the cache is empty; the card shows
      // the cached value or "0" rather than crashing.
      return StartupBundleService.balanceCoins ?? 0;
    }
  }

  /// Manual refresh (pull-to-refresh + after returning from Watch Ad).
  void _reloadBalance() {
    if (!mounted) return;
    setState(() {
      _balance = _loadBalance();
    });
  }

  /// Rs equivalent of a coin balance (1 coin = Rs 0.01), formatted
  /// without trailing zeros (1000 coins -> "10", 1050 coins -> "10.50").
  String _rsValue(int coins) {
    final double rs = coins / 100;
    return rs == rs.roundToDouble()
        ? rs.toInt().toString()
        : rs.toStringAsFixed(2);
  }

  Widget _balanceCard(AppLocalizations t) {
    return Card(
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
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(t.balanceLoadFailed),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _reloadBalance,
                        child: Text(t.retry),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                final int coins = snapshot.data!;
                return Column(
                  children: [
                    Text(
                      '$coins',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      t.coins,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    // Coins stay primary; the ≈Rs equivalent is
                    // secondary (1 coin = Rs 0.01). Restored per
                    // Jaani, 29 Oct 2026 ("Rs rehny do").
                    Text(
                      t.balanceRsApprox(_rsValue(coins)),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          _reloadBalance();
          // Wait for the refreshed future so the indicator spins until
          // the new balance actually lands (bounded by the Supabase
          // _guard timeout — never an infinite spinner).
          try {
            await _balance.timeout(const Duration(seconds: 30));
          } catch (_) {
            // The FutureBuilder shows the error/retry state itself.
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _balanceCard(t),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WatchAdScreen(),
                    ),
                  ).then((_) {
                    // Refresh balance after returning from Watch Ad
                    _reloadBalance();
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
      ),
    );
  }
}
