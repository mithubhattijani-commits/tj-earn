import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/referral_deep_link_service.dart';
import '../services/remote_config_service.dart';
import '../services/startup_bundle_service.dart';
import '../services/supabase_service.dart';
import '../services/updater_service.dart';
import '../services/unity_ads_service.dart';
import 'admin_screen.dart';
import 'articles_tab.dart';
import 'referral_tab.dart';
import 'settings_tab.dart';
import 'withdraw_tab.dart';
import 'watch_ad_screen.dart';

/// v1.0.20 shell (Jaani, 3 Nov 2026): website <-> app integration.
///
/// Built on the PROVEN v1.0.19 shell (no ANR on Jaani's phone).
/// Five tabs:
/// - Home: balance display + Watch Ad button (v1.0.17 code, unchanged)
/// - Articles: read nigraantv.xyz articles, earn +10 coins each (cap 5/day)
///   via the SAME submit-reading Edge Function the website uses — shared
///   balance, shared cap. This is why the app exists: grow website audience.
/// - Refer: simple referral (code/share/apply/direct list/claim)
/// - Withdraw: payout request form + history
/// - Settings: language, Check for Update, admin panel, logout, support
///
/// Doner-style update (Jaani, 3 Nov 2026 — "jesy Doner update hoti ha
/// wesy"): admin + update icons always visible in the AppBar (like
/// Doner), plus a silent launch update check. Website manifest at
/// https://nigraantv.xyz/apps/tj-earn-version.json.
///
/// EXCLUDED per Jaani: spin wheel, daily tasks, leaderboard.
///
/// ANR safety: tabs are created lazily (only when first opened), each tab
/// owns its own Future with a hard timeout — no concurrent startup burst,
/// no infinite spinners.
///
/// Task D (Jaani, 12 Nov 2026): remote config is wired into THIS shell —
/// the announcement banner above the tabs, the display name + logo in the
/// AppBar, and the force_update flag triggers the existing updater flow.
/// The config is re-fetched on launch, on resume and every ~60s (see
/// RemoteConfigService). The Adsterra banner in the orphan home_tab.dart
/// is untouched, as is the Unity banner below.
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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  // Lazily-created tab widgets: index 0 = home, 1 = articles,
  // 2 = referral, 3 = withdraw. Settings (4) is rebuilt fresh so a
  // language change always reaches it.
  var _index = 0;
  final List<Widget?> _tabs = <Widget?>[null, null, null, null];

  // Remote config (Task D, 12 Nov 2026): the minVersionCode already
  // prompted for, so the update dialog does not re-fire on every 60s
  // poll while the same forced version is live.
  int? _forceUpdatePromptedFor;

  @override
  void initState() {
    super.initState();
    // Doner-style launch update check (Jaani, 3 Nov 2026): silent unless
    // a newer version exists. Non-blocking, never touches the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdaterService.checkForUpdate(context);
    });
    // Referral deep link auto-apply (Jaani, 3 Nov 2026): if the user
    // arrived via a referral link (?ref=CODE), the code was stored as
    // pending at startup. Auto-apply it now that they're signed in —
    // no manual code entry needed. Best-effort, never blocks UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoApplyReferral();
    });
    // Remote config (Task D, 12 Nov 2026): listen for fresh config and
    // re-fetch it on resume; the 60s poll runs in RemoteConfigService.
    WidgetsBinding.instance.addObserver(this);
    RemoteConfigService.instance.notifier.addListener(_onRemoteConfig);
    RemoteConfigService.instance.startPolling();
    // The cached config may already carry a force_update — check it once
    // the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeForceUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RemoteConfigService.instance.notifier.removeListener(_onRemoteConfig);
    RemoteConfigService.instance.stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume (and, via the 60s poll, reconnect): fetch the config fresh
    // — the announcement, name, logo or force-update flag can change
    // while the app is in the background.
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteConfigService.instance.refresh());
    }
  }

  /// A fresh config landed (launch fetch, resume refresh or 60s poll):
  /// re-check the force-update flag.
  void _onRemoteConfig() {
    _maybeForceUpdate();
  }

  /// Force update (Task D): when the config's force_update flag is on,
  /// run the EXISTING updater flow — it fetches the website manifest and
  /// prompts for the update when a newer versionCode exists. Nothing new
  /// is invented here. Prompted once per forced version per shell
  /// lifetime (the poll would otherwise re-fire it).
  void _maybeForceUpdate() {
    if (!mounted) return;
    final force = RemoteConfigService.instance.config.forceUpdate;
    if (!force.enabled || force.minVersionCode <= 0) return;
    if (_forceUpdatePromptedFor == force.minVersionCode) return;
    _forceUpdatePromptedFor = force.minVersionCode;
    unawaited(UpdaterService.checkForUpdate(context));
  }

  /// Remote-config announcement banner (Task D): a slim notice bar at
  /// the top of the mounted shell, shown only when the config
  /// announcement is enabled and non-empty. It listens to the config
  /// notifier, so it appears and updates without a restart.
  Widget _announcementBanner() {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (context, config, _) {
        final announcement = config.announcement;
        if (!announcement.show) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  announcement.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Auto-applies a pending referral code from a deep link.
  /// Shows a confirmation snackbar on success. Silent on failure —
  /// the user can still apply manually in the Refer tab.
  Future<void> _autoApplyReferral() async {
    try {
      final code =
          await ReferralDeepLinkService.instance.autoApplyPendingCode().timeout(
            const Duration(seconds: 30),
          );
      if (code != null && mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t?.referAutoApplied(code) ?? 'Referral $code applied! 🎉',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      // Silent: manual apply remains available in the Refer tab.
    }
  }

  Widget _tab(int i) {
    if (i == 4) {
      return SettingsTab(
        key: const ValueKey('settings'),
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
      );
    }
    var w = _tabs[i];
    if (w == null) {
      w = switch (i) {
        0 => _HomeTab(key: const ValueKey('home')),
        1 => const ArticlesTab(key: ValueKey('articles')),
        2 => const ReferralTab(key: ValueKey('referral')),
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
      appBar: AppBar(
        title: ValueListenableBuilder<RemoteConfig>(
          valueListenable: RemoteConfigService.instance.notifier,
          builder: (context, config, _) {
            // Remote-config display name + logo (Task D): the config
            // name/logo replace the app name/logo in the mounted
            // shell's AppBar; the localized app title is the fallback.
            final name = config.displayName.trim().isNotEmpty
                ? config.displayName
                : t.appTitle;
            final logo = config.logoUrl.trim();
            if (logo.isEmpty) return Text(name);
            return Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    logo,
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: t.adminTitle,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: t.checkForUpdate,
            onPressed: () => UpdaterService.checkManually(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Remote-config announcement (Task D): shows in the mounted
          // shell whenever the config announcement is non-empty.
          _announcementBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [_tab(0), _tab(1), _tab(2), _tab(3), _tab(4)],
            ),
          ),
          // Unity banner ad (BP_Banner_Android) in the mounted shell,
          // above the bottom navigation bar — one slot shared by all 5
          // tabs, gated per tab by the remote-config zone for the
          // active tab (tj-earn.json "ads"). The Adsterra banner in
          // the orphan home_tab.dart is untouched.
          ZonedUnityBanner(
            zone: (ads) => switch (_index) {
              0 => ads.bannerHome,
              1 => ads.bannerArticles,
              2 => ads.bannerReferral,
              3 => ads.bannerWithdraw,
              4 => ads.bannerSettings,
              _ => true,
            },
          ),
        ],
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
            icon: const Icon(Icons.article_outlined),
            label: 'Articles',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.group_add),
            label: t.referTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.payments),
            label: t.withdrawTitle,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: t.settingsTitle,
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
