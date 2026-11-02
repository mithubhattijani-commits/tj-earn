import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/admin_status.dart';
import '../services/remote_config_service.dart';
import '../services/updater_service.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'home_tab.dart';
import 'offers_tab.dart';
import 'referral_tab.dart';
import 'settings_tab.dart';
import 'wallet_tab.dart';
import 'withdraw_tab.dart';

/// Bottom-navigation shell shown after login.
///
/// Remote Config (Jaani, 2 Nov 2026): the AppBar title/logo, the
/// announcement bar under the header, and the force-update kill-switch
/// are all server-driven — UI listens to [RemoteConfigService.notifier]
/// so a fresh fetch updates the screen without a restart.
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
  var _updateChecked = false;
  var _forceUpdateDialogShown = false;

  @override
  void initState() {
    super.initState();
    // Re-check the kill-switch whenever fresh config arrives (cache load
    // at startup, then the 6h background refresh).
    RemoteConfigService.instance.notifier.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    RemoteConfigService.instance.notifier.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    // ignore: unawaited_futures
    _checkForceUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_updateChecked) {
      _updateChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // ignore: unawaited_futures
        UpdaterService.checkForUpdate(context);
        // ignore: unawaited_futures
        _checkForceUpdate();
      });
    }
  }

  /// Force-update kill-switch: when enabled and the installed versionCode
  /// is below the server's min_version_code, show a NON-DISMISSIBLE
  /// dialog whose Update button hands off to the existing in-app updater
  /// flow. Never throws, never blocks, shows once per session.
  Future<void> _checkForceUpdate() async {
    if (_forceUpdateDialogShown) {
      return;
    }
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final int currentCode = int.tryParse(info.buildNumber) ?? 0;
      final RemoteConfig cfg = RemoteConfigService.instance.config;
      if (!cfg.forceUpdate.enabled) {
        return;
      }
      if (currentCode >= cfg.forceUpdate.minVersionCode) {
        return;
      }
      _forceUpdateDialogShown = true;
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context)!;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(localizations.updateAvailable),
            content: const Text(
              'A required update is available. Please update TJ Earn to '
              'continue.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // Hand off to the existing in-app updater flow
                  // (version check -> download -> install).
                  // ignore: unawaited_futures
                  UpdaterService.checkForUpdate(ctx);
                },
                child: Text(localizations.updateNow),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Kill-switch checks must never break the app: fail silently.
    }
  }

  /// Slim notice bar under the header. Visible only when the server
  /// enables it AND provides non-empty text.
  Widget _announcementBar() {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (BuildContext context, RemoteConfig cfg, _) {
        if (!cfg.announcement.show) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: TjEarnTheme.goldDeep.withValues(alpha: 0.25),
            border: Border(
              bottom: BorderSide(
                color: TjEarnTheme.gold.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.campaign,
                color: TjEarnTheme.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cfg.announcement.text,
                  style: const TextStyle(color: TjEarnTheme.gold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// AppBar title driven by Remote Config: server `display_name`
  /// (empty = localized bundled default) and `logo_url` (empty = no
  /// logo; load failures fall back to title-only, never an error).
  Widget _appBarTitle(AppLocalizations t) {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: RemoteConfigService.instance.notifier,
      builder: (BuildContext context, RemoteConfig cfg, _) {
        final String titleText = cfg.displayName.trim().isNotEmpty
            ? cfg.displayName.trim()
            : t.appTitle;
        final String logoUrl = cfg.logoUrl.trim();
        if (logoUrl.isEmpty) {
          return Text(titleText);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                logoUrl,
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                titleText,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // The Admin tab is VISIBLE only for admins (probed once per session).
    // Non-admins never see the entry; the server gate stays the real guard.
    return ValueListenableBuilder<bool?>(
      valueListenable: AdminStatus.notifier,
      builder: (BuildContext context, bool? isAdmin, _) {
        final showAdmin = isAdmin == true;
        final tabCount = showAdmin ? 7 : 6;
        final index = _index >= tabCount ? 0 : _index;
        return Scaffold(
          appBar: (showAdmin && index == 6)
              ? null
              : AppBar(title: _appBarTitle(t)),
          body: Column(
            children: [
              _announcementBar(),
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: [
                    HomeTab(onNavigate: (i) => setState(() => _index = i)),
                    const ReferralTab(),
                    const OffersTab(),
                    WalletTab(onEarnTap: () => setState(() => _index = 2)),
                    const WithdrawTab(),
                    SettingsTab(
                      locale: widget.locale,
                      onLocaleChanged: widget.onLocaleChanged,
                    ),
                    if (showAdmin) const AdminScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: index,
            onTap: (i) => setState(() => _index = i),
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                  icon: const Icon(Icons.home), label: t.homeTitle),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.group_add), label: t.referTab),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.card_giftcard),
                  label: t.offersTitle),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.account_balance_wallet),
                  label: t.walletTitle),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.payments), label: t.withdrawTitle),
              BottomNavigationBarItem(
                  icon: const Icon(Icons.settings),
                  label: t.settingsTitle),
              if (showAdmin)
                BottomNavigationBarItem(
                    icon: const Icon(Icons.admin_panel_settings),
                    label: t.adminNavLabel),
            ],
          ),
        );
      },
    );
  }
}
