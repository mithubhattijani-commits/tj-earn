import 'package:flutter/material.dart';
import 'package:tj_earn/l10n/app_localizations.dart';

import '../services/updater_service.dart';
import 'home_tab.dart';
import 'offers_tab.dart';
import 'referral_tab.dart';
import 'settings_tab.dart';
import 'wallet_tab.dart';
import 'withdraw_tab.dart';

/// Bottom-navigation shell shown after login.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_updateChecked) {
      _updateChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) UpdaterService.checkForUpdate(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle)),
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(onNavigate: (i) => setState(() => _index = i)),
          const ReferralTab(),
          const OffersTab(),
          const WalletTab(),
          const WithdrawTab(),
          SettingsTab(
            locale: widget.locale,
            onLocaleChanged: widget.onLocaleChanged,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: t.homeTitle),
          BottomNavigationBarItem(icon: const Icon(Icons.group_add), label: t.referTab),
          BottomNavigationBarItem(icon: const Icon(Icons.card_giftcard), label: t.offersTitle),
          BottomNavigationBarItem(icon: const Icon(Icons.account_balance_wallet), label: t.walletTitle),
          BottomNavigationBarItem(icon: const Icon(Icons.payments), label: t.withdrawTitle),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: t.settingsTitle),
        ],
      ),
    );
  }
}
