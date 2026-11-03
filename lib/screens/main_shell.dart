import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/startup_bundle_service.dart';
import '../services/supabase_service.dart';
import 'referral_tab.dart';
import 'withdraw_tab.dart';
import 'watch_ad_screen.dart';

/// v1.0.18 simple shell (Jaani, 3 Nov 2026).
///
/// Built on the PROVEN v1.0.17 minimal shell (no ANR on Jaani's phone).
/// Three tabs, nothing else:
/// - Home: balance display + Watch Ad button (v1.0.17 code, unchanged)
/// - Refer: simple referral (code/share/apply/direct list/claim)
/// - Withdraw: payout request form + history
///
/// EXCLUDED per Jaani: spin wheel, daily tasks, leaderboard.
///
/// ANR safety: tabs are created lazily (only when first opened), each tab
/// owns its own Future with a hard timeout — no concurrent startup burst,
/// no infinite spinners.
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
  var _index = 0;
  // Lazily-created tab widgets: index 0 = home, 1 = referral, 2 = withdraw.
  final List<Widget?> _tabs = <Widget?>[null, null, null];

  Widget _tab(int i) {
    var w = _tabs[i];
    if (w == null) {
      w = switch (i) {
        0 => _HomeTab(key: const ValueKey('home')),
        1 => const ReferralTab(key: ValueKey('referral')),
        _ => const WithdrawTab(key: ValueKey('withdraw')),
      };
      _tabs[i] = w;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: IndexedStack(
        index: _index,
        children: [_tab(0), _tab(1), _tab(2)],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: t.homeTitle,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.group_add),
            label: t.referTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.payments),
            label: t.withdrawTitle,
          ),
        ],
      ),
    );
  }
}

/// Home tab: v1.0.17 balance + Watch Ad UI, byte-for-byte behaviour.
/// Extracted into its own widget so the shell can lazy-load tabs.
class _HomeTab extends StatefulWidget {
  const _HomeTab({super.key});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
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
    return RefreshIndicator(
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
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const WatchAdScreen(),
                      ),
                    )
                    .then((_) {
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
    );
  }
}
