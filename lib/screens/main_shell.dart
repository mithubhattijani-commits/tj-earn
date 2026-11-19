import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/referral_deep_link_service.dart';
import '../services/remote_config_service.dart';
import '../services/startup_bundle_service.dart';
import '../services/supabase_service.dart';
import '../services/updater_service.dart';
import '../services/unity_ads_service.dart';
import 'admin_screen.dart';
import 'articles_tab.dart';
import 'games_screen.dart';
import 'referral_tab.dart';
import 'settings_tab.dart';
import 'withdraw_tab.dart';

/// v1.0.20 shell (Jaani, 3 Nov 2026): website <-> app integration.
///
/// Built on the PROVEN v1.0.19 shell (no ANR on Jaani's phone).
/// Five tabs:
/// - Home: balance display + daily check-in (compliant model, v1.0.25)
/// - Articles: read nigraantv.xyz articles, earn +5 coins each (cap
///   200/day, unique articles only) via the `submit-reading` Edge
///   Function. This is why the app exists: grow website audience.
/// - Refer: simple referral (code/share/apply/direct list/claim)
/// - Withdraw: payout request form + history (min 10,000 coins = Rs 100)
/// - Settings: language, Check for Update, admin panel, logout, support
///
/// Compliant model (v1.0.25, Unity ticket #00945584): NO coin ever comes
/// from an ad. The Watch Ad screen and the Unity rewarded placement are
/// removed. Ads that remain are non-rewarded only: the Unity banner in
/// this shell, interstitials between articles, App Open on cold start,
/// and the Adsterra banner on Home.
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
    // Compliant-model notice (v1.0.25): once, after the update, tell the
    // user coins now come only from reading — old balance is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowModelNotice();
    });
  }

  /// Shows the one-time compliant-model notice (v1.0.25).
  ///
  /// Guarded by a SharedPreferences flag, so it appears exactly once per
  /// install after the update — never on every launch. The body text is
  /// the user's exact approved wording, identical in both locales.
  Future<void> _maybeShowModelNotice() async {
    const flag = 'compliant_model_notice_shown_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flag) == true) return;
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t?.modelNoticeTitle ?? 'TJ Earn update'),
          content: Text(
            t?.modelNoticeBody ??
                'Coins ab sirf articles parhne se milen ge — aap ka purana balance mehfooz hai.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t?.modelNoticeOk ?? 'Theek hai'),
            ),
          ],
        ),
      );
      await prefs.setBool(flag, true);
    } catch (_) {
      // Never break startup for a notice — silent if anything fails.
    }
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
          // above the bottom navigation bar. The Adsterra banner in
          // the orphan home_tab.dart is untouched.
          const UnityBannerAdWidget(),
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
  bool _checkingIn = false;
  String? _checkinMessage;
  bool _checkinIsError = false;

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

  /// Manual refresh (pull-to-refresh + after check-in).
  void _reloadBalance() {
    if (!mounted) return;
    setState(() {
      _balance = _loadBalance();
    });
  }

  /// Daily check-in (compliant model, v1.0.25): replaces the removed
  /// Watch Ad button. Coins come from the `claim-checkin` Edge Function
  /// (server amount is authoritative); the button only renders the
  /// result. A 409 (already checked in today) is returned as data by
  /// [SupabaseService.claimCheckin], not thrown.
  Future<void> _doCheckin() async {
    if (_checkingIn) return;
    setState(() {
      _checkingIn = true;
      _checkinMessage = null;
      _checkinIsError = false;
    });
    try {
      final t = AppLocalizations.of(context)!;
      final Map<String, dynamic> res =
          await SupabaseService.claimCheckin();
      if (!mounted) return;
      final Object? coins = res['coins'];
      final bool already = res['already'] == true;
      setState(() {
        _checkinMessage = already
            ? t.checkinAlready
            : (coins is int
                ? t.checkinDone(coins)
                : t.checkinDoneNoCoins);
      });
      _reloadBalance();
    } catch (_) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      setState(() {
        _checkinMessage = t.checkinFailed;
        _checkinIsError = true;
      });
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
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
              onPressed: _checkingIn ? null : _doCheckin,
              icon: _checkingIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.event_available),
              label: Text(
                _checkingIn ? t.checkinChecking : t.checkinButton,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if (_checkinMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _checkinMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _checkinIsError
                      ? Theme.of(context).colorScheme.error
                      : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            // Play & Earn (RapidoReach wall, v1.0.25): shown only when
            // the server enables it in remote config — the wall needs
            // the `rapidoreach-wall-url` Edge Function deployed and
            // RAPIDOREACH_APP_ID / RAPIDOREACH_APP_KEY set. Listens to
            // the config notifier so the tile appears without a restart
            // once the operator flips the switch.
            ValueListenableBuilder<RemoteConfig>(
              valueListenable: RemoteConfigService.instance.notifier,
              builder: (context, config, _) {
                if (!config.rapidoreach.enabled) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (config.rapidoreach.enabled) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const GamesScreen(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.sports_esports,
                                  size: 40,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.gamesTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(t.gamesSubtitle),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
